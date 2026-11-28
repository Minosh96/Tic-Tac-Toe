package com.melowlabs.melow_tic_tac_toe

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.os.PowerManager
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration

/**
 * Native Android Background Service (`foregroundServiceType="remoteMessaging"`)
 * that maintains direct native Cloud Firestore listeners on `melow-game` for:
 * 1. Incoming 1-on-1 & 5-person Group Voice Calls (`calls`)
 * 2. Unread 1-on-1 Direct Chat Messages (`chats`)
 * 3. Unread Group Chat Messages (`groups`)
 * 4. Incoming Friend Requests (`friendRequests`)
 * 5. Incoming Match Challenges (`friendChallenges`)
 *
 * Because this service runs natively in Android even when the phone is locked,
 * the screen is off, or the user is in another app (like YouTube, Chrome, or WhatsApp),
 * incoming calls and messages ring and pop up immediately just like WhatsApp!
 */
class MelowRealtimeAlertService : Service() {
    companion object {
        const val EXTRA_UID = "extra_uid"

        fun start(context: Context, uid: String? = null) {
            try {
                val appCtx = context.applicationContext
                val intent = Intent(appCtx, MelowRealtimeAlertService::class.java).apply {
                    if (!uid.isNullOrEmpty()) {
                        putExtra(EXTRA_UID, uid)
                    }
                }
                appCtx.startService(intent)
            } catch (_: Exception) {
            }
        }

        fun startIfLoggedIn(context: Context) {
            try {
                if (FirebaseApp.getApps(context).isEmpty()) {
                    FirebaseApp.initializeApp(context)
                }
                val uid = FirebaseAuth.getInstance().currentUser?.uid
                if (!uid.isNullOrEmpty()) {
                    start(context, uid)
                }
            } catch (_: Exception) {
            }
        }

        fun stop(context: Context) {
            try {
                val appCtx = context.applicationContext
                appCtx.stopService(Intent(appCtx, MelowRealtimeAlertService::class.java))
            } catch (_: Exception) {
            }
        }
    }

    private var cpuWakeLock: PowerManager.WakeLock? = null
    private var watchedUid: String = ""
    private var callsListener: ListenerRegistration? = null
    private var chatsListener: ListenerRegistration? = null
    private var groupsListener: ListenerRegistration? = null
    private var requestsListener: ListenerRegistration? = null
    private var challengesListener: ListenerRegistration? = null
    private var authListener: FirebaseAuth.AuthStateListener? = null

    private val activeRingingCalls = mutableSetOf<String>()
    private var chatsSeeded = false
    private val lastChatMsgMs = mutableMapOf<String, Long>()
    private var groupsSeeded = false
    private val lastGroupMsgMs = mutableMapOf<String, Long>()
    private var requestsSeeded = false
    private val notifiedRequests = mutableSetOf<String>()
    private var challengesSeeded = false
    private val notifiedChallenges = mutableSetOf<String>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        acquireBackgroundWakeLock()
        ensureFirebaseAndAttachListeners(null)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        acquireBackgroundWakeLock()
        val passedUid = intent?.getStringExtra(EXTRA_UID)
        ensureFirebaseAndAttachListeners(passedUid)
        return START_STICKY
    }

    private fun acquireBackgroundWakeLock() {
        try {
            MelowNotificationHelper.ensureChannels(this)
            if (cpuWakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                cpuWakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "melow:realtime_alert_standby"
                ).apply {
                    setReferenceCounted(false)
                }
            }
            if (cpuWakeLock?.isHeld == false) {
                // Keep CPU awake in background so Firestore listeners fire while phone is locked
                cpuWakeLock?.acquire(12 * 60 * 60 * 1000L)
            }
        } catch (_: Exception) {
        }
    }

    private fun ensureFirebaseAndAttachListeners(explicitUid: String?) {
        try {
            if (FirebaseApp.getApps(this).isEmpty()) {
                FirebaseApp.initializeApp(this)
            }
            val auth = FirebaseAuth.getInstance()
            if (authListener == null) {
                val listener = FirebaseAuth.AuthStateListener { firebaseAuth ->
                    val nextUid = firebaseAuth.currentUser?.uid ?: ""
                    if (nextUid.isNotEmpty() && nextUid != watchedUid) {
                        attachFirestoreListenersForUid(nextUid)
                    } else if (nextUid.isEmpty()) {
                        clearListeners()
                    }
                }
                authListener = listener
                auth.addAuthStateListener(listener)
            }
            val targetUid = if (!explicitUid.isNullOrEmpty()) {
                explicitUid
            } else {
                auth.currentUser?.uid ?: ""
            }
            if (targetUid.isNotEmpty() && targetUid != watchedUid) {
                attachFirestoreListenersForUid(targetUid)
            }
        } catch (_: Exception) {
        }
    }

    private fun attachFirestoreListenersForUid(uid: String) {
        clearListeners()
        watchedUid = uid

        val db = try {
            FirebaseFirestore.getInstance(FirebaseApp.getInstance(), "melow-game")
        } catch (_: Exception) {
            return
        }

        // 1. Live Incoming 1-on-1 & Group Voice Calls
        callsListener = db.collection("calls")
            .whereEqualTo("calleeUid", uid)
            .addSnapshotListener { snap, err ->
                if (err != null || snap == null) return@addSnapshotListener
                val nowMs = System.currentTimeMillis()
                val currentlyRinging = mutableSetOf<String>()

                for (doc in snap.documents) {
                    val status = doc.getString("status") ?: ""
                    if (status != "ringing") continue
                    val createdAt = doc.getTimestamp("createdAt")
                    if (createdAt != null && (nowMs - createdAt.toDate().time) > 180_000L) {
                        continue
                    }
                    val callId = doc.id
                    currentlyRinging.add(callId)
                    if (activeRingingCalls.add(callId)) {
                        val callerName = doc.getString("callerName") ?: "Friend"
                        val groupId = doc.getString("groupId")
                        val groupName = doc.getString("groupName")
                        val isGroup = !groupId.isNullOrBlank()
                        MelowNotificationHelper.showCallNotification(
                            context = this@MelowRealtimeAlertService,
                            callId = callId,
                            callerName = callerName,
                            isGroupCall = isGroup,
                            groupName = groupName
                        )
                    }
                }

                val stoppedRinging = activeRingingCalls - currentlyRinging
                for (oldCallId in stoppedRinging) {
                    MelowNotificationHelper.cancelCallNotification(
                        this@MelowRealtimeAlertService,
                        oldCallId
                    )
                }
                activeRingingCalls.clear()
                activeRingingCalls.addAll(currentlyRinging)
            }

        // 2. Live Direct 1-on-1 Chat Messages
        chatsListener = db.collection("chats")
            .whereArrayContains("participants", uid)
            .addSnapshotListener { snap, err ->
                if (err != null || snap == null) return@addSnapshotListener
                if (!chatsSeeded) {
                    chatsSeeded = true
                    for (doc in snap.documents) {
                        val ts = doc.getTimestamp("lastMessageAt")?.toDate()?.time ?: 0L
                        lastChatMsgMs[doc.id] = ts
                    }
                    return@addSnapshotListener
                }

                for (doc in snap.documents) {
                    val ts = doc.getTimestamp("lastMessageAt")?.toDate()?.time ?: 0L
                    val prevTs = lastChatMsgMs[doc.id] ?: 0L
                    if (ts <= prevTs) continue
                    lastChatMsgMs[doc.id] = ts

                    val lastSenderUid = doc.getString("lastSenderUid") ?: ""
                    if (lastSenderUid == uid || lastSenderUid.isEmpty()) continue

                    // Skip if user is actively viewing this exact chat in the foreground
                    val participants = (doc.get("participants") as? List<*>)
                        ?.mapNotNull { it?.toString() } ?: emptyList()
                    val otherUid = participants.firstOrNull { it != uid } ?: ""
                    if (MainActivity.isInForeground &&
                        MainActivity.activeChatFriendUid == otherUid &&
                        otherUid.isNotEmpty()
                    ) {
                        continue
                    }

                    val unreadCounts = doc.get("unreadCounts") as? Map<*, *>
                    val unreadForMe = (unreadCounts?.get(uid) as? Number)?.toInt() ?: 1
                    if (unreadForMe <= 0) continue

                    val senderName = doc.getString("lastSenderName")?.takeIf { it.isNotBlank() }
                        ?: "New Message"
                    val lastMessage = doc.getString("lastMessage")?.takeIf { it.isNotBlank() }
                        ?: "Sent you a message"
                    val title = if (unreadForMe > 1) {
                        "💬 $senderName ($unreadForMe new messages)"
                    } else {
                        "💬 $senderName"
                    }
                    MelowNotificationHelper.showMessageNotification(
                        context = this@MelowRealtimeAlertService,
                        notifId = MelowNotificationHelper.messageNotificationId(doc.id),
                        title = title,
                        body = lastMessage,
                        count = unreadForMe
                    )
                }
            }

        // 3. Live Group Chat Messages
        groupsListener = db.collection("groups")
            .whereArrayContains("memberUids", uid)
            .addSnapshotListener { snap, err ->
                if (err != null || snap == null) return@addSnapshotListener
                if (!groupsSeeded) {
                    groupsSeeded = true
                    for (doc in snap.documents) {
                        val ts = doc.getTimestamp("lastMessageAt")?.toDate()?.time ?: 0L
                        lastGroupMsgMs[doc.id] = ts
                    }
                    return@addSnapshotListener
                }

                for (doc in snap.documents) {
                    val ts = doc.getTimestamp("lastMessageAt")?.toDate()?.time ?: 0L
                    val prevTs = lastGroupMsgMs[doc.id] ?: 0L
                    if (ts <= prevTs) continue
                    lastGroupMsgMs[doc.id] = ts

                    val lastSenderUid = doc.getString("lastSenderUid") ?: ""
                    if (lastSenderUid == uid || lastSenderUid.isEmpty()) continue

                    val groupName = doc.getString("name") ?: "Friend Group"
                    val senderName = doc.getString("lastSenderName")?.takeIf { it.isNotBlank() }
                        ?: "Member"
                    val lastMessage = doc.getString("lastMessage")?.takeIf { it.isNotBlank() }
                        ?: "New group message"
                    MelowNotificationHelper.showMessageNotification(
                        context = this@MelowRealtimeAlertService,
                        notifId = MelowNotificationHelper.messageNotificationId("grp_${doc.id}"),
                        title = "👥 $groupName • $senderName",
                        body = lastMessage,
                        count = 1
                    )
                }
            }

        // 4. Live Incoming Friend Requests
        requestsListener = db.collection("friendRequests")
            .whereEqualTo("receiverUid", uid)
            .addSnapshotListener { snap, err ->
                if (err != null || snap == null) return@addSnapshotListener
                if (!requestsSeeded) {
                    requestsSeeded = true
                    for (doc in snap.documents) {
                        if (doc.getString("status") == "pending") {
                            notifiedRequests.add(doc.id)
                        }
                    }
                    return@addSnapshotListener
                }

                for (doc in snap.documents) {
                    if (doc.getString("status") != "pending") continue
                    if (notifiedRequests.add(doc.id)) {
                        val senderName = doc.getString("senderName") ?: "A player"
                        MelowNotificationHelper.showMessageNotification(
                            context = this@MelowRealtimeAlertService,
                            notifId = MelowNotificationHelper.messageNotificationId("req_${doc.id}"),
                            title = "👋 New Friend Request",
                            body = "$senderName sent you a friend request!",
                            count = 1
                        )
                    }
                }
            }

        // 5. Live Incoming Match Challenges
        challengesListener = db.collection("friendChallenges")
            .whereEqualTo("receiverUid", uid)
            .addSnapshotListener { snap, err ->
                if (err != null || snap == null) return@addSnapshotListener
                if (!challengesSeeded) {
                    challengesSeeded = true
                    for (doc in snap.documents) {
                        if (doc.getString("status") == "pending") {
                            notifiedChallenges.add(doc.id)
                        }
                    }
                    return@addSnapshotListener
                }

                for (doc in snap.documents) {
                    if (doc.getString("status") != "pending") continue
                    if (notifiedChallenges.add(doc.id)) {
                        val senderName = doc.getString("senderName") ?: "A friend"
                        val size = (doc.getLong("boardSize") ?: 3L).toInt()
                        MelowNotificationHelper.showMessageNotification(
                            context = this@MelowRealtimeAlertService,
                            notifId = MelowNotificationHelper.messageNotificationId("chal_${doc.id}"),
                            title = "⚔️ Match Challenge",
                            body = "$senderName challenged you to a ${size}×${size} match!",
                            count = 1
                        )
                    }
                }
            }
    }

    private fun clearListeners() {
        callsListener?.remove()
        callsListener = null
        chatsListener?.remove()
        chatsListener = null
        groupsListener?.remove()
        groupsListener = null
        requestsListener?.remove()
        requestsListener = null
        challengesListener?.remove()
        challengesListener = null
        watchedUid = ""
        activeRingingCalls.clear()
        chatsSeeded = false
        lastChatMsgMs.clear()
        groupsSeeded = false
        lastGroupMsgMs.clear()
        requestsSeeded = false
        notifiedRequests.clear()
        challengesSeeded = false
        notifiedChallenges.clear()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Keep listening in background even if the user swipes the app from Recents!
        startIfLoggedIn(applicationContext)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        try {
            if (cpuWakeLock?.isHeld == true) {
                cpuWakeLock?.release()
            }
        } catch (_: Exception) {
        }
        cpuWakeLock = null
        val auth = try {
            FirebaseAuth.getInstance()
        } catch (_: Exception) {
            null
        }
        authListener?.let { auth?.removeAuthStateListener(it) }
        authListener = null
        clearListeners()
        super.onDestroy()
    }
}
