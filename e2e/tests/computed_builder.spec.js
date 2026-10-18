// @ts-check
//
// The computed-field formula builder on /editor/fields: a recipe written from
// dropdowns, then finished by hand in the formula view with the insert
// palette.
//
// `FieldDefinitionLiveTest` drives the builder's form params directly, which
// proves what the server does with a recipe and nothing about the palette:
// inserting a function or a value at the caret is the colocated
// `.FormulaEditor` hook, which only a browser runs.
const { test, expect, signInAsAdmin } = require("./fixtures");

test.describe("computed field builder", () => {
  /** @type {string} */
  let name;

  test.beforeEach(async ({ page }) => {
    name = `e2e_computed_${Date.now()}`;
    await signInAsAdmin(page);
  });

  test.afterEach(async ({ page }) => {
    await page.goto("/editor/fields");
    const field = page.locator(`li[id^="field-"]`).filter({ has: page.locator(`code:text-is("${name}")`) });
    if (await field.count()) {
      page.once("dialog", dialog => dialog.accept());
      await field.getByRole("button", { name: "Delete field" }).click();
      await expect(field).toHaveCount(0);
    }
  });

  test("a recipe writes the formula, and the palette edits it at the caret", async ({ page }) => {
    await page.goto("/editor/fields");
    const form = page.locator("#new-field-form");
    await form.getByLabel("Page", { exact: true }).check();
    await form.locator('select[name="field_definition[field_type]"]').selectOption("computed");

    // The recipe view: pick one, fill its blanks.
    const builder = page.locator("#new-field-builder");
    await builder.getByText("Value with a label", { exact: true }).click();
    await page.locator("#new-field-slot-value").selectOption("title");
    await page.locator("#new-field-slot-prefix").fill("About:");
    await page.locator("#new-field-slot-prefix").blur();
    await expect(builder.getByText("{{ title }}", { exact: false })).toBeVisible();
    await expect(page.locator("#new-field-preview output")).toContainText("About:");
    if (process.env.SHOT_DIR) await builder.screenshot({ path: `${process.env.SHOT_DIR}/recipe.png` });

    // The formula view keeps what the recipe wrote.
    await builder.getByRole("radiogroup").getByText("Formula", { exact: true }).click();
    const formula = page.locator("#new-field-compute");
    await expect(formula).toHaveValue("About: {{ title }}");

    // Outside an expression a function arrives wrapped in {{ }}, with the caret
    // between its parentheses; a value clicked there goes inside the call.
    await formula.fill("Shout: ");
    await builder.locator('button[data-insert-fn="upcase"]').click();
    await expect(formula).toHaveValue("Shout: {{ upcase() }}");
    await builder.locator('button[data-insert-ref="title"]').click();
    await expect(formula).toHaveValue("Shout: {{ upcase(title) }}");
    await expect(page.locator("#new-field-preview output")).toHaveText(/^Shout: [^a-z]*$/);

    // A typo shows in the preview before anything is saved.
    await formula.fill("{{ upcse(title) }}");
    await expect(page.locator("#new-field-preview")).toContainText("calls unknown function upcse/1");
    await formula.fill("Shout: {{ upcase(title) }}");
    await expect(page.locator("#new-field-preview output")).toBeVisible();
    if (process.env.SHOT_DIR) await builder.screenshot({ path: `${process.env.SHOT_DIR}/formula.png` });

    await form.locator('input[name="field_definition[label]"]').fill("Shout");
    await form.locator('input[name="field_definition[name]"]').fill(name);
    await form.locator("button[type=submit]").click();

    const saved = page.locator(`li[id^="field-"]`).filter({ has: page.locator(`code:text-is("${name}")`) });
    await expect(saved).toContainText("Shout: {{ upcase(title) }}");
  });
});
