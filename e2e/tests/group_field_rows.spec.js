// @ts-check
//
// A repeating `:group` field's rows in the content editor: added, typed into,
// reordered by dragging a row's handle (the shared `Sortable` hook, with
// `data-sort-event="group_row_reorder"`), and saved in that order.
// `GroupFieldEditorTest` pushes the reorder event itself, which proves what
// the server does with an order and nothing about whether a drag produces one
// — or whether the typed values follow their row once LiveView patches the
// index-keyed rows back into place.
const { test, expect, signInAsAdmin, newDraftContent, saveDraft } = require("./fixtures");

test.describe("group field rows", () => {
  /** @type {string} */
  let stamp;
  /** @type {string} */
  let name;

  test.beforeEach(async ({ page }) => {
    stamp = String(Date.now());
    name = `e2e_rows_${stamp}`;
    await signInAsAdmin(page);
  });

  test.afterEach(async ({ page }) => {
    await page.goto("/editor");
    const rows = page.locator(`li[id^="${name}-"]`).filter({ hasText: stamp });
    if (await rows.count()) {
      for (const row of await rows.all()) await row.getByRole("checkbox").check();
      await page.locator('button[phx-click="bulk"][phx-value-action="delete"]').click();
      await page.locator('button[phx-click="confirm_bulk"]').click();
      await expect(rows).toHaveCount(0);
    }

    await page.goto("/editor/fields");
    const field = page.locator('li[id^="field-"]').filter({ has: page.locator(`code:text-is("${name}_doses")`) });
    if (await field.count()) {
      page.once("dialog", dialog => dialog.accept());
      await field.getByRole("button", { name: "Delete field", exact: true }).click();
      await expect(field).toHaveCount(0);
    }

    await page.goto("/editor/types");
    const type = page.locator("li[id^='type-']").filter({ hasText: name });
    if (await type.count()) {
      page.once("dialog", dialog => dialog.accept());
      await type.getByRole("button", { name: "Archive content type" }).click();
      await expect(type).toHaveCount(0);
    }
  });

  /** A type with a repeating group of two sub-fields. @param {import("@playwright/test").Page} page */
  async function createTypeWithRows(page) {
    await page.goto("/editor/types");
    await page.fill('#new-type-form input[name="type_definition[label]"]', `E2E Rows ${stamp}`);
    await page.fill('#new-type-form input[name="type_definition[plural_label]"]', `E2E Rows ${stamp}s`);
    await page.fill('#new-type-form input[name="type_definition[name]"]', name);
    await page.locator("#new-type-form").getByRole("button", { name: "Create content type" }).click();
    await expect(page).toHaveURL(/\/editor\/fields\?type=def/);

    await page.fill('#new-field-form input[name="field_definition[label]"]', "Doses");
    await page.fill('#new-field-form input[name="field_definition[name]"]', `${name}_doses`);
    await page.selectOption('#new-field-form select[name="field_definition[field_type]"]', "group");
    await page.locator("#new-field-multiple-true").check();
    await page.locator("#new-field-form button[type=submit]").click();

    const field = page.locator('li[id^="field-"]').filter({ has: page.locator(`code:text-is("${name}_doses")`) });
    await expect(field).toBeVisible();

    for (const [label, type] of [["Amount", "string"], ["Unit", "string"]]) {
      await field.getByRole("button", { name: "Add a field" }).click();
      const form = field.locator('form[id^="link-field-form-new-"]');
      await form.locator('input[name="link_field[label]"]').fill(label);
      await form.locator('select[name="link_field[field_type]"]').selectOption(type);
      await form.getByRole("button", { name: "Save field" }).click();
      await expect(field.locator(`code:text-is("${label.toLowerCase()}")`)).toBeVisible();
    }
  }

  test("add rows, drag one above another, and the order saves", async ({ page }) => {
    await createTypeWithRows(page);
    await newDraftContent(page, name);

    const field = `${name}_doses`;
    const rows = page.locator(`#custom-field-${field}-rows > li`);
    const amounts = () => rows.locator(`input[name$="[amount]"]`).evaluateAll(els => els.map(el => /** @type {HTMLInputElement} */ (el).value));

    for (const amount of ["first", "second", "third"]) {
      await page.locator(`#custom-field-${field}-add`).click();
      await expect(rows).toHaveCount(["first", "second", "third"].indexOf(amount) + 1);
      await rows.last().locator('input[name$="[amount]"]').fill(amount);
      await rows.last().locator('input[name$="[unit]"]').fill(`${amount} unit`);
    }

    await expect.poll(amounts).toEqual(["first", "second", "third"]);

    // Drag "third" by its handle onto the top of "first".
    await rows.nth(2).locator("[data-drag-handle]").dragTo(rows.nth(0), { targetPosition: { x: 20, y: 4 } });
    await expect.poll(amounts).toEqual(["third", "first", "second"]);
    // Each row's other value moved with it.
    await expect(rows.nth(0).locator('input[name$="[unit]"]')).toHaveValue("third unit");

    await saveDraft(page, { title: `Rows ${stamp}`, slug: `rows-${stamp}` });
    await page.reload();
    await expect.poll(amounts).toEqual(["third", "first", "second"]);
    await expect(rows.nth(0).locator('input[name$="[unit]"]')).toHaveValue("third unit");
  });
});
