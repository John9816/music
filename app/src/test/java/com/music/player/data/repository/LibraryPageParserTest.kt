package com.music.player.data.repository

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LibraryPageParserTest {

    @Test
    fun emptyPageStops() {
        assertFalse(
            LibraryPageParser.shouldFetchNextPage(
                page = 0,
                pageSize = 100,
                pageItemCount = 0
            )
        )
    }

    @Test
    fun partialPageIsLast() {
        assertFalse(
            LibraryPageParser.shouldFetchNextPage(
                page = 0,
                pageSize = 100,
                pageItemCount = 40
            )
        )
    }

    @Test
    fun fullPageContinuesWhenNoTotals() {
        assertTrue(
            LibraryPageParser.shouldFetchNextPage(
                page = 0,
                pageSize = 100,
                pageItemCount = 100
            )
        )
    }

    @Test
    fun stopsWhenTotalElementsCovered() {
        assertFalse(
            LibraryPageParser.shouldFetchNextPage(
                page = 1,
                pageSize = 100,
                pageItemCount = 100,
                totalElements = 200
            )
        )
        assertTrue(
            LibraryPageParser.shouldFetchNextPage(
                page = 0,
                pageSize = 100,
                pageItemCount = 100,
                totalElements = 200
            )
        )
    }

    @Test
    fun stopsWhenNextPageExceedsTotalPages() {
        assertFalse(
            LibraryPageParser.shouldFetchNextPage(
                page = 2,
                pageSize = 50,
                pageItemCount = 50,
                totalPages = 3
            )
        )
        assertTrue(
            LibraryPageParser.shouldFetchNextPage(
                page = 1,
                pageSize = 50,
                pageItemCount = 50,
                totalPages = 3
            )
        )
    }

    @Test
    fun respectsMaxPagesCap() {
        assertFalse(
            LibraryPageParser.shouldFetchNextPage(
                page = LibraryPageParser.MAX_PAGES - 1,
                pageSize = 100,
                pageItemCount = 100,
                maxPages = LibraryPageParser.MAX_PAGES
            )
        )
    }

    @Test
    fun readTotalElementsPrefersAliases() {
        assertEquals(
            250,
            LibraryPageParser.readTotalElements(mapOf("totalElements" to 250))
        )
        assertEquals(
            12,
            LibraryPageParser.readTotalElements(mapOf("totalCount" to "12"))
        )
        assertEquals(
            7,
            LibraryPageParser.readTotalElements(mapOf("count" to 7L))
        )
        assertNull(LibraryPageParser.readTotalElements(mapOf("foo" to 1)))
        assertNull(LibraryPageParser.readTotalElements(mapOf("total" to -1)))
    }

    @Test
    fun readTotalPagesPrefersAliases() {
        assertEquals(
            5,
            LibraryPageParser.readTotalPages(mapOf("totalPages" to 5))
        )
        assertEquals(
            3,
            LibraryPageParser.readTotalPages(mapOf("pages" to "3"))
        )
        assertEquals(
            9,
            LibraryPageParser.readTotalPages(mapOf("pageCount" to 9))
        )
        assertNull(LibraryPageParser.readTotalPages(emptyMap()))
    }
}
