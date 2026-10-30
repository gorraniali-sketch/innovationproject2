import assert from "node:assert/strict";
import test from "node:test";
import {
  getAuthRedirectPath,
  isValidEmail,
  isValidPassword,
  normalizeEmail,
} from "../src/lib/supabase/auth-validation.ts";

test("normalizes and validates email addresses", () => {
  assert.equal(normalizeEmail("  Person@Example.com "), "person@example.com");
  assert.equal(isValidEmail("person@example.com"), true);
  assert.equal(isValidEmail("not-an-email"), false);
  assert.equal(isValidEmail("person @example.com"), false);
  assert.equal(isValidEmail(`a${"b".repeat(250)}@example.com`), false);
});

test("enforces password length limits", () => {
  assert.equal(isValidPassword("12345678"), true);
  assert.equal(isValidPassword("1234567"), false);
  assert.equal(isValidPassword("x".repeat(129)), false);
});

test("allows only known internal callback destinations", () => {
  assert.equal(
    getAuthRedirectPath("/auth/update-password"),
    "/auth/update-password",
  );
  assert.equal(getAuthRedirectPath("/auth/confirmed"), "/auth/confirmed");
  assert.equal(getAuthRedirectPath("https://example.com"), "/auth/confirmed");
  assert.equal(getAuthRedirectPath("//example.com"), "/auth/confirmed");
  assert.equal(getAuthRedirectPath(null), "/auth/confirmed");
});
