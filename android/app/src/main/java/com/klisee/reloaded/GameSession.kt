package com.klisee.reloaded

/** Prevents save backups/restores from racing against a still-running native game. */
object GameSession {
    @Volatile var active: Boolean = false
        internal set
}
