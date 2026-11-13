#!/usr/bin/env node

/**
 * Checks a second-look answer against the pile it was given.
 * Usage: node validate-second-look.cjs <input.json> <answer.json>
 *
 * Fails when the answer is not one JSON object with `items` and `new_candidates`
 * arrays, when an item has no item_id or an unknown verdict, or when any
 * set-aside item from the input has no answer: a skipped item was never re-read.
 */

const fs = require("fs");

const VERDICTS = new Set(["not_a_finding", "needs_validation", "confirmed"]);

const [inputPath, answerPath] = process.argv.slice(2);
if (!inputPath || !answerPath) {
  console.error("usage: node validate-second-look.cjs <input.json> <answer.json>");
  process.exit(2);
}

const pile = JSON.parse(fs.readFileSync(inputPath, "utf8"));
let answer = null;
try {
  answer = JSON.parse(fs.readFileSync(answerPath, "utf8"));
} catch (error) {
  console.error(`second look: answer is not JSON: ${error.message}`);
  process.exit(1);
}

const errors = [];
if (!answer || typeof answer !== "object" || !Array.isArray(answer.items) || !Array.isArray(answer.new_candidates)) {
  errors.push("answer must be one JSON object with an items array and a new_candidates array");
} else {
  const answered = new Set();
  for (const item of answer.items) {
    if (!item || typeof item.item_id !== "string" || !VERDICTS.has(item.verdict)) {
      errors.push(`item has no item_id or an unknown verdict: ${JSON.stringify(item).slice(0, 200)}`);
      continue;
    }
    answered.add(item.item_id);
  }
  const missing = pile.map((entry) => entry.item_id).filter((id) => !answered.has(id));
  if (missing.length > 0) {
    errors.push(`${missing.length} of ${pile.length} set-aside items have no answer: ${missing.join(", ")}`);
  }
}

if (errors.length > 0) {
  for (const error of errors) console.error(`second look: ${error}`);
  process.exit(1);
}
console.log(`second look: all ${pile.length} set-aside items answered`);
