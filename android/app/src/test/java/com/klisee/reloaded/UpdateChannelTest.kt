package com.klisee.reloaded

import org.junit.Assert.assertEquals
import org.junit.Test

class UpdateChannelTest {
    @Test fun customBuildsUseTheForkReleaseChannel() {
        val fork = "lionelmendozaparsons020-lab/pokemon-reloaded-android"
        assertEquals(fork, Update.repositoryFor("0.3.9-ui.24"))
        assertEquals(fork, Update.repositoryFor("0.3.9-controles"))
    }
    @Test fun upstreamBuildsKeepTheirOriginalReleaseChannel() {
        assertEquals("Klisee/pokemon-reloaded-android", Update.repositoryFor("0.3.9"))
    }
}
