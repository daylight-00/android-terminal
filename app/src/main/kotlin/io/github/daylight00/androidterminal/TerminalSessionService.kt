package io.github.daylight00.androidterminal

import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.IBinder
import java.util.UUID

/**
 * Layer 2 process/session host. The PTY belongs to this service rather than to an Activity
 * or WebView, allowing a replacement frontend to attach to the same native shell process.
 */
class TerminalSessionService : Service() {
    internal interface Client {
        fun onOutput(
            connectionGeneration: Long,
            sessionId: String,
            record: TerminalOutputRecord,
        )

        fun onState(
            connectionGeneration: Long,
            sessionId: String,
            state: TerminalSessionState,
            exitCode: Int?,
            failure: String?,
        )
    }

    internal inner class LocalBinder : Binder() {
        fun attach(
            client: Client,
            rows: Int,
            columns: Int,
            pixelWidth: Int,
            pixelHeight: Int,
        ): TerminalAttachment = this@TerminalSessionService.attach(
            client,
            TerminalDimensions(rows, columns, pixelWidth, pixelHeight),
        )

        fun detach(client: Client, connectionGeneration: Long, sessionId: String) {
            this@TerminalSessionService.detach(client, connectionGeneration, sessionId)
        }

        fun write(
            connectionGeneration: Long,
            sessionId: String,
            bytes: ByteArray,
        ) {
            withCurrentAttachment(connectionGeneration, sessionId) { activeSession ->
                activeSession.write(bytes)
            }
        }

        fun resize(
            connectionGeneration: Long,
            sessionId: String,
            rows: Int,
            columns: Int,
            pixelWidth: Int,
            pixelHeight: Int,
        ) {
            resizeCurrentAttachment(
                connectionGeneration,
                sessionId,
                TerminalDimensions(rows, columns, pixelWidth, pixelHeight),
            )
        }

        fun updateSerializedSnapshot(
            connectionGeneration: Long,
            sessionId: String,
            throughSequence: Long,
            bytes: ByteArray,
        ): Boolean = this@TerminalSessionService.updateSerializedSnapshot(
            connectionGeneration,
            sessionId,
            throughSequence,
            bytes,
        )
    }

    private val binder = LocalBinder()
    private val lock = Any()
    private val replayBuffer = SessionReplayBuffer(REPLAY_LIMIT_BYTES)
    private val serializedSnapshotStore = TerminalSerializedSnapshotStore(TerminalContract.MAX_SERIALIZED_SNAPSHOT_BYTES)
    private val geometryState = TerminalGeometryState()

    private var session: TerminalSession? = null
    private var sessionEpoch = 0L
    private var sessionId = ""
    private var state = TerminalSessionState.IDLE
    private var exitCode: Int? = null
    private var failure: String? = null

    private var client: Client? = null
    private var connectionGeneration = 0L

    override fun onBind(intent: Intent): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        val active = synchronized(lock) {
            client = null
            connectionGeneration += 1L
            sessionEpoch += 1L
            val current = session
            session = null
            state = TerminalSessionState.CLOSED
            geometryState.reset()
            current
        }
        active?.close()
        super.onDestroy()
    }

    private fun attach(client: Client, candidate: TerminalDimensions): TerminalAttachment {
        var startSession: Pair<TerminalSession, TerminalDimensions>? = null
        var resizeSession: Pair<TerminalSession, TerminalDimensions>? = null
        val attachment = synchronized(lock) {
            val accepted = geometryState.accept(candidate)
            val currentSize = requireNotNull(accepted ?: geometryState.snapshot()) {
                "terminal attachment geometry is unavailable"
            }

            connectionGeneration += 1L
            this.client = client

            if (state == TerminalSessionState.IDLE) {
                startSession = Pair(createSessionLocked(), currentSize)
            } else if (
                accepted != null &&
                (state == TerminalSessionState.STARTING || state == TerminalSessionState.RUNNING)
            ) {
                val activeSession = session
                if (activeSession != null) resizeSession = Pair(activeSession, accepted)
            }

            val serializedSnapshot = serializedSnapshotStore.snapshot()
            val snapshotTail = serializedSnapshot?.let {
                replayBuffer.snapshotAfter(it.throughSequence)
            }
            val snapshotUsable = serializedSnapshot != null && snapshotTail?.available == true
            val replay = if (snapshotUsable) {
                requireNotNull(snapshotTail)
            } else {
                replayBuffer.snapshotAfter(0L)
            }
            TerminalAttachment(
                connectionGeneration = connectionGeneration,
                sessionId = sessionId,
                state = state,
                exitCode = exitCode,
                failure = failure,
                serializedSnapshot = if (snapshotUsable) serializedSnapshot?.bytes else null,
                serializedThroughSequence = if (snapshotUsable) {
                    serializedSnapshot?.throughSequence ?: 0L
                } else {
                    0L
                },
                replayAvailable = replay.available,
                replayTruncated = replay.truncated || (serializedSnapshot != null && !snapshotUsable),
                replayRecords = replay.records,
                nextSequence = replay.nextSequence,
            )
        }

        startSession?.let { (activeSession, size) ->
            activeSession.start(size.rows, size.columns, size.pixelWidth, size.pixelHeight)
        }
        resizeSession?.let { (activeSession, size) ->
            activeSession.resize(size.rows, size.columns, size.pixelWidth, size.pixelHeight)
        }
        return attachment
    }

    private fun detach(client: Client, generation: Long, expectedSessionId: String) {
        synchronized(lock) {
            if (this.client !== client) return
            if (connectionGeneration != generation || sessionId != expectedSessionId) return
            this.client = null
        }
    }

    private fun resizeCurrentAttachment(
        generation: Long,
        expectedSessionId: String,
        candidate: TerminalDimensions,
    ) {
        val resized = synchronized(lock) {
            if (generation != connectionGeneration || expectedSessionId != sessionId) return
            if (state != TerminalSessionState.STARTING && state != TerminalSessionState.RUNNING) return
            val accepted = geometryState.accept(candidate) ?: return
            val activeSession = session ?: return
            Pair(activeSession, accepted)
        }
        resized.first.resize(
            resized.second.rows,
            resized.second.columns,
            resized.second.pixelWidth,
            resized.second.pixelHeight,
        )
    }

    private fun updateSerializedSnapshot(
        generation: Long,
        expectedSessionId: String,
        throughSequence: Long,
        bytes: ByteArray,
    ): Boolean = synchronized(lock) {
        if (generation != connectionGeneration || expectedSessionId != sessionId) return false
        if (state != TerminalSessionState.STARTING && state != TerminalSessionState.RUNNING) return false
        serializedSnapshotStore.update(
            throughSequence = throughSequence,
            latestSequence = replayBuffer.latestSequence(),
            bytes = bytes,
        )
    }

    private fun withCurrentAttachment(
        generation: Long,
        expectedSessionId: String,
        action: (TerminalSession) -> Unit,
    ) {
        val current = synchronized(lock) {
            if (generation != connectionGeneration || expectedSessionId != sessionId) return
            if (state != TerminalSessionState.STARTING && state != TerminalSessionState.RUNNING) return
            session
        }
        if (current != null) action(current)
    }

    private fun createSessionLocked(): TerminalSession {
        sessionEpoch += 1L
        val epoch = sessionEpoch
        sessionId = UUID.randomUUID().toString()
        state = TerminalSessionState.STARTING
        exitCode = null
        failure = null
        replayBuffer.reset()
        serializedSnapshotStore.reset()

        return TerminalSession(
            homeDirectory = filesDir,
            temporaryDirectory = cacheDir,
            listener = object : TerminalSession.Listener {
                override fun onStarted() = handleStarted(epoch)
                override fun onOutput(bytes: ByteArray) = handleOutput(epoch, bytes)
                override fun onExit(exitCode: Int) = handleExit(epoch, exitCode)
                override fun onFailure(error: Throwable) = handleFailure(epoch, error)
            },
        ).also { session = it }
    }

    private fun handleStarted(epoch: Long) {
        val notification = synchronized(lock) {
            if (epoch != sessionEpoch || state != TerminalSessionState.STARTING) return
            state = TerminalSessionState.RUNNING
            stateNotificationLocked()
        }
        notification.deliver()
    }

    private fun handleOutput(epoch: Long, bytes: ByteArray) {
        if (bytes.isEmpty()) return
        val notification = synchronized(lock) {
            if (epoch != sessionEpoch) return
            val record = replayBuffer.append(bytes)
            val currentClient = client ?: return
            OutputNotification(currentClient, connectionGeneration, sessionId, record)
        }
        notification.deliver()
    }

    private fun handleExit(epoch: Long, code: Int) {
        val notification = synchronized(lock) {
            if (epoch != sessionEpoch) return
            session = null
            state = TerminalSessionState.EXITED
            exitCode = code
            failure = null
            stateNotificationLocked()
        }
        notification.deliver()
    }

    private fun handleFailure(epoch: Long, error: Throwable) {
        val notification = synchronized(lock) {
            if (epoch != sessionEpoch) return
            session = null
            state = TerminalSessionState.FAILED
            exitCode = null
            failure = error.message ?: error.javaClass.simpleName
            stateNotificationLocked()
        }
        notification.deliver()
    }

    private fun stateNotificationLocked(): StateNotification {
        val currentClient = client
        return StateNotification(
            client = currentClient,
            connectionGeneration = connectionGeneration,
            sessionId = sessionId,
            state = state,
            exitCode = exitCode,
            failure = failure,
        )
    }

    private data class OutputNotification(
        val client: Client,
        val connectionGeneration: Long,
        val sessionId: String,
        val record: TerminalOutputRecord,
    ) {
        fun deliver() = client.onOutput(connectionGeneration, sessionId, record)
    }

    private data class StateNotification(
        val client: Client?,
        val connectionGeneration: Long,
        val sessionId: String,
        val state: TerminalSessionState,
        val exitCode: Int?,
        val failure: String?,
    ) {
        fun deliver() {
            client?.onState(connectionGeneration, sessionId, state, exitCode, failure)
        }
    }

    private companion object {
        const val REPLAY_LIMIT_BYTES = 1024 * 1024
    }
}

internal enum class TerminalSessionState(val wireName: String) {
    IDLE("idle"),
    STARTING("starting"),
    RUNNING("running"),
    EXITED("exited"),
    FAILED("failed"),
    CLOSED("closed"),
}

internal data class TerminalAttachment(
    val connectionGeneration: Long,
    val sessionId: String,
    val state: TerminalSessionState,
    val exitCode: Int?,
    val failure: String?,
    val serializedSnapshot: ByteArray?,
    val serializedThroughSequence: Long,
    val replayAvailable: Boolean,
    val replayTruncated: Boolean,
    val replayRecords: List<TerminalOutputRecord>,
    val nextSequence: Long,
)
