package com.cheroliv.magicstick

import com.microsoft.playwright.Browser
import com.microsoft.playwright.Page
import com.microsoft.playwright.Playwright
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.TestInstance
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.EnumSource
import java.io.File

@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class A11yAudit {

    private lateinit var playwright: Playwright
    private lateinit var browser: Browser
    private lateinit var axeCoreJs: String

    private val bakeDir: String =
        System.getenv("BAKE_DIR") ?: File("build/bake").absolutePath

    private val pages = listOf(
        "index.html", "quick-start.html", "ab-partition.html",
        "scripts.html", "about.html", "blog.html"
    )

    enum class Theme(val dataAttr: String) {
        LIGHT("light"), DARK("dark"), HIGH_CONTRAST("high-contrast")
    }

    data class Violation(
        val id: String,
        val impact: String,
        val description: String,
        val helpUrl: String,
        val nodes: List<NodeResult>
    )

    data class NodeResult(
        val html: String,
        val target: String,
        val failureSummary: String
    )

    data class PageAuditResult(
        val theme: Theme,
        val page: String,
        val violations: List<Violation>,
        val violationCount: Int
    )

    @BeforeAll
    fun setup() {
        axeCoreJs = javaClass.getResource("/axe-core.js")?.readText()
            ?: error("axe-core.js not found in resources")
        playwright = Playwright.create()
        browser = playwright.chromium().launch()
    }

    @AfterAll
    fun teardown() {
        browser.close()
        playwright.close()
    }

    private fun runAxeOnPage(page: Page, pagePath: String, theme: Theme): PageAuditResult {
        val url = "file://$bakeDir/$pagePath"
        page.navigate(url)
        page.waitForLoadState()

        page.evaluate("""() => {
            localStorage.setItem('preferred-theme', '${theme.dataAttr}');
            document.documentElement.setAttribute('data-bs-theme', '${theme.dataAttr}');
        }""")
        page.waitForTimeout(500.0)

        page.evaluate(axeCoreJs)
        val raw = page.evaluate("""() => {
            return new Promise((resolve) => {
                axe.run({
                    runOnly: {
                        type: 'tag',
                        values: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa', 'best-practice']
                    }
                }).then(results => {
                    const simplified = results.violations.map(v => ({
                        id: v.id,
                        impact: v.impact,
                        description: v.description,
                        helpUrl: v.helpUrl,
                        nodes: v.nodes.map(n => ({
                            html: n.html.substring(0, 200),
                            target: n.target.join(' > '),
                            failureSummary: (n.failureSummary || '').substring(0, 300)
                        }))
                    }));
                    resolve(JSON.stringify({
                        violations: simplified,
                        violationCount: results.violations.length
                    }));
                });
            });
        }""") as String

        return parseResult(raw, theme, pagePath)
    }

    private fun parseResult(json: String, theme: Theme, pagePath: String): PageAuditResult {
        val violations = mutableListOf<Violation>()

        val violationPattern = Regex("""\{"id":"([^"]+)","impact":"([^"]+)","description":"([^"]+)","helpUrl":"([^"]+)","nodes":\[([^\]]*)\]\}""")
        val nodePattern = Regex("""\{"html":"(.*?)","target":"(.*?)","failureSummary":"(.*?)"\}""")

        violationPattern.findAll(json).forEach { match ->
            val id = match.groupValues[1]
            val impact = match.groupValues[2]
            val description = match.groupValues[3]
            val helpUrl = match.groupValues[4]
            val nodesStr = match.groupValues[5]

            val nodes = nodePattern.findAll(nodesStr).map { nodeMatch ->
                NodeResult(
                    html = nodeMatch.groupValues[1].replace("\\\"", "\"").replace("\\\\", "\\"),
                    target = nodeMatch.groupValues[2],
                    failureSummary = nodeMatch.groupValues[3].replace("\\n", "\n").replace("\\\"", "\"")
                )
            }.toList()

            violations.add(Violation(id, impact, description, helpUrl, nodes))
        }

        val violationCountMatch = Regex(""""violationCount":(\d+)""").find(json)
        val violationCount = violationCountMatch?.groupValues?.get(1)?.toDouble()?.toInt() ?: violations.size

        return PageAuditResult(theme, pagePath, violations, violationCount)
    }

    @ParameterizedTest
    @EnumSource(Theme::class)
    fun `audit site accessibility across all pages`(theme: Theme) {
        val context = browser.newContext()
        val page = context.newPage()
        val allResults = mutableListOf<PageAuditResult>()
        val failedPages = mutableListOf<String>()

        for (pagePath in pages) {
            try {
                val result = runAxeOnPage(page, pagePath, theme)
                allResults.add(result)
                if (result.violations.isNotEmpty()) {
                    failedPages.add(pagePath)
                }
            } catch (e: Exception) {
                println("WARNING: Could not audit $pagePath with theme ${theme.name}: ${e.message}")
            }
        }

        printReport(theme, allResults)

        val contrastViolations = allResults.flatMap { it.violations }
            .filter { it.id == "color-contrast" }

        if (contrastViolations.isNotEmpty()) {
            val details = contrastViolations.joinToString("\n") { v ->
                "  - ${v.description}\n    Nodes: ${v.nodes.joinToString("; ") { it.target }}"
            }
            org.junit.jupiter.api.Assertions.fail<String>(
                "Contrast violations found for theme ${theme.name}:\n$details"
            )
        }

        context.close()
    }

    private fun printReport(theme: Theme, results: List<PageAuditResult>) {
        println("\n${"=".repeat(80)}")
        println("  ACCESSIBILITY AUDIT — Theme: ${theme.name}")
        println("${"=".repeat(80)}")

        val totalViolations = results.sumOf { it.violations.size }

        if (totalViolations == 0) {
            println("  ✅ No violations found across ${results.size} pages!")
        } else {
            println("  ❌ $totalViolations violation(s) found across ${results.size} pages:")
            results.filter { it.violations.isNotEmpty() }.forEach { result ->
                println("\n  📄 ${result.page} (${result.violations.size} violations):")
                result.violations.forEach { v ->
                    println("    - [${v.impact}] ${v.id}: ${v.description}")
                    v.nodes.take(3).forEach { n ->
                        println("      → ${n.target}")
                        println("        ${n.failureSummary.lines().first()}")
                    }
                    if (v.nodes.size > 3) println("      ... and ${v.nodes.size - 3} more")
                }
            }
        }
        println("${"=".repeat(80)}\n")
    }
}