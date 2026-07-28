export const PROGRAMMER_ROLES = {
  typescript: "typescript-programmer",
  rust: "rust-programmer",
  go: "go-programmer",
} as const;

export type ProgrammingBackground = keyof typeof PROGRAMMER_ROLES;
export type ReaderLocale = "ja" | "en";
