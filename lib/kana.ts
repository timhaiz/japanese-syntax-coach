import dictionary from './kana-dictionary.json'

const allReadings = { ...dictionary.readings, ...dictionary.extraReadings }
const keys = Object.keys(allReadings)
  .filter((key) => /[一-龯々]/.test(key))
  .sort((a, b) => b.length - a.length)
const keyPattern = new RegExp(keys.map((key) => key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|'), 'g')

/** Adds parenthesized kana to Japanese kanji words for display only. */
export function withKana(value: string): string {
  // Chinese instructions are intentionally left untouched. Japanese exercise
  // text normally contains kana; standalone vocabulary tokens are still
  // handled when the whole value is a dictionary entry.
  if (!/[ぁ-ゖァ-ヺ]/.test(value) && !allReadings[value]) return value
  // Match against the original string in one pass. Replacing dictionary
  // entries one by one would re-scan inserted kana and produce nested or
  // malformed annotations (for example 日本語 → 日本（ほん）語).
  return value.replace(keyPattern, (match) => `${match}（${allReadings[match]}）`)
}
