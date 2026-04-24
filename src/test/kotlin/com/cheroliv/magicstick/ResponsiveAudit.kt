package com.cheroliv.magicstick

import com.microsoft.playwright.Browser
import com.microsoft.playwright.Playwright
import com.microsoft.playwright.Browser.NewContextOptions
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.TestInstance
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.EnumSource
import java.io.File

@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class ResponsiveAudit {

    private lateinit var playwright: Playwright
    private lateinit var browser: Browser

    private val bakeDir: String =
        System.getenv("BAKE_DIR") ?: File("build/bake").absolutePath

    private val pages = listOf("index.html", "quick-start.html", "about.html")

    enum class Viewport(val label: String, val width: Int, val height: Int) {
        MOBILE("Mobile 375x812", 375, 812),
        TABLET("Tablet 768x1024", 768, 1024),
        DESKTOP("Desktop 1440x900", 1440, 900)
    }

    @BeforeAll
    fun setup() {
        playwright = Playwright.create()
        browser = playwright.chromium().launch()
    }

    @AfterAll
    fun teardown() {
        browser.close()
        playwright.close()
    }

    private fun createContext(vp: Viewport) =
        browser.newContext(NewContextOptions().setViewportSize(vp.width, vp.height))

    @ParameterizedTest
    @EnumSource(Viewport::class)
    fun `check no horizontal overflow across viewports`(viewport: Viewport) {
        val context = createContext(viewport)
        val page = context.newPage()

        for (pagePath in pages) {
            val url = "file://$bakeDir/$pagePath"
            page.navigate(url)
            page.waitForLoadState()

            val scrollWidth = page.evaluate("() => document.documentElement.scrollWidth") as Int
            val clientWidth = page.evaluate("() => document.documentElement.clientWidth") as Int

            if (scrollWidth > clientWidth + 1) {
                println("  ⚠️  HORIZONTAL OVERFLOW on $pagePath at ${viewport.label}: " +
                    "scrollWidth=$scrollWidth > clientWidth=$clientWidth")
            }

            org.junit.jupiter.api.Assertions.assertTrue(
                scrollWidth <= clientWidth + 1,
                "Horizontal overflow detected on $pagePath at ${viewport.label}: " +
                    "scrollWidth=$scrollWidth > clientWidth=$clientWidth"
            )
        }

        context.close()
    }

    @ParameterizedTest
    @EnumSource(Viewport::class)
    fun `check visible text not clipped across viewports`(viewport: Viewport) {
        val context = createContext(viewport)
        val page = context.newPage()

        for (pagePath in pages) {
            val url = "file://$bakeDir/$pagePath"
            page.navigate(url)
            page.waitForLoadState()

            val result = page.evaluate("""() => {
                const els = document.querySelectorAll('h1, h2, h3, h4, p, a');
                let clipped = [];
                els.forEach(el => {
                    if (el.textContent.trim() === '' && !el.querySelector('i, img, svg')) return;
                    const style = window.getComputedStyle(el);
                    if (style.display === 'none' || style.visibility === 'hidden') return;
                    if (el.closest('.navbar-collapse') && !el.closest('.navbar-collapse').classList.contains('show')) return;
                    const rect = el.getBoundingClientRect();
                    if (rect.width <= 0 || rect.height <= 0) {
                        clipped.push(el.tagName + '.' + el.className + ' [' + el.textContent.substring(0, 30) + ']');
                    }
                });
                return JSON.stringify(clipped);
            }""") as String

            val clippedElements = if (result.startsWith("[")) result else "[]"
            org.junit.jupiter.api.Assertions.assertEquals(
                "[]", clippedElements,
                "Text elements clipped/invisible on $pagePath at ${viewport.label}: $clippedElements"
            )
        }

        context.close()
    }
}