import { createMemo, createSignal, For, render, Show } from "@luna_ui/luna";

import {
  parse,
  parseFolddown,
  type FolddownContentFilter,
  type FolddownReaderProfile,
} from "../js/api.js";
import {
  PROGRAMMER_ROLES,
  type ProgrammingBackground,
  type ReaderLocale,
} from "../frontend/folddown/reader-profile";
import { viewerNodesFromManifest } from "../frontend/folddown/from-mdx";
import { moonbitForProgrammersSource } from "../frontend/folddown/moonbit-documents";
import {
  createInitialCollapsedState,
  selectNodesForReader,
  type FoldNode,
} from "../frontend/folddown/model";
import { MarkdownRenderer } from "./ast-renderer";
import "./folddown.css";

const moonbitForProgrammersManifest = parseFolddown(moonbitForProgrammersSource);
if (moonbitForProgrammersManifest.diagnostics.length > 0) {
  const errors = moonbitForProgrammersManifest.diagnostics
    .map((diagnostic) => `${diagnostic.code}: ${diagnostic.message}`)
    .join("\n");
  throw new Error(`Invalid Folddown document:\n${errors}`);
}
const moonbitForProgrammersNodes = viewerNodesFromManifest(moonbitForProgrammersManifest.nodes);
const moonbitReaderProfiles = moonbitForProgrammersManifest.readerProfiles;
if (moonbitReaderProfiles.length !== 2) {
  throw new Error("Folddown viewer requires exactly two reader profiles.");
}
const moonbitContentFilters = moonbitForProgrammersManifest.contentFilters;
if (moonbitContentFilters.length !== 2) {
  throw new Error("Folddown viewer requires exactly two content filters.");
}

type ViewerCopy = {
  background: string;
  language: string;
  readerState: string;
  readingIntent: string;
  kind: Record<FoldNode["kind"], string>;
  assumedKnown: string;
  prerequisite: string;
  evidence: string;
  open: string;
  close: string;
  title: Record<ProgrammingBackground, string>;
  documentTitle: string;
  declarationCount: (count: number) => string;
};

const viewerCopy: Record<ReaderLocale, ViewerCopy> = {
  ja: {
    background: "経験言語",
    language: "表示言語",
    readerState: "知っていること",
    readingIntent: "読み方",
    kind: { concept: "概念", procedure: "手順", reference: "参照", evidence: "証跡" },
    assumedKnown: "既知として省略",
    prerequisite: "前提",
    evidence: "証跡",
    open: "開く",
    close: "閉じる",
    title: {
      typescript: "TypeScript 経験者のための MoonBit 入門",
      rust: "Rust 経験者のための MoonBit 入門",
      go: "Go 経験者のための MoonBit 入門",
    },
    documentTitle: "MoonBit の基礎",
    declarationCount: (count) => `${count} 個の節`,
  },
  en: {
    background: "Background",
    language: "Reading language",
    readerState: "What you know",
    readingIntent: "Reading focus",
    kind: { concept: "Concept", procedure: "Procedure", reference: "Reference", evidence: "Evidence" },
    assumedKnown: "Assumed known",
    prerequisite: "Requires",
    evidence: "Evidence",
    open: "Open",
    close: "Close",
    title: {
      typescript: "MoonBit for TypeScript programmers",
      rust: "MoonBit for Rust programmers",
      go: "MoonBit for Go programmers",
    },
    documentTitle: "MoonBit fundamentals",
    declarationCount: (count) => `${count} declarations`,
  },
};

function ReaderAudienceControls(props: {
  locale: () => ReaderLocale;
  background: () => ProgrammingBackground;
  readerProfileId: () => string;
  readerProfiles: FolddownReaderProfile[];
  contentFilterId: () => string;
  contentFilters: FolddownContentFilter[];
  onLocaleChange: (locale: ReaderLocale) => void;
  onBackgroundChange: (background: ProgrammingBackground) => void;
  onReaderProfileChange: (profileId: string) => void;
  onContentFilterChange: (filterId: string) => void;
}) {
  const copy = createMemo(() => viewerCopy[props.locale()]);

  return (
    <div class="reader-audience-controls">
      <div class="profile-choice">
        <span class="profile-choice-label">{() => copy().background}</span>
        <div class="segmented-control" role="group" aria-label={() => copy().background}>
          <button
            class={() => `segment ${props.background() === "typescript" ? "is-selected" : ""}`}
            type="button"
            aria-pressed={() => props.background() === "typescript"}
            onClick={() => props.onBackgroundChange("typescript")}
          >
            TypeScript
          </button>
          <button
            class={() => `segment ${props.background() === "rust" ? "is-selected" : ""}`}
            type="button"
            aria-pressed={() => props.background() === "rust"}
            onClick={() => props.onBackgroundChange("rust")}
          >
            Rust
          </button>
          <button
            class={() => `segment ${props.background() === "go" ? "is-selected" : ""}`}
            type="button"
            aria-pressed={() => props.background() === "go"}
            onClick={() => props.onBackgroundChange("go")}
          >
            Go
          </button>
        </div>
      </div>
      <div class="profile-choice">
        <span class="profile-choice-label">{() => copy().language}</span>
        <div class="segmented-control" role="group" aria-label={() => copy().language}>
          <button
            class={() => `segment ${props.locale() === "ja" ? "is-selected" : ""}`}
            type="button"
            aria-pressed={() => props.locale() === "ja"}
            onClick={() => props.onLocaleChange("ja")}
          >
            日本語
          </button>
          <button
            class={() => `segment ${props.locale() === "en" ? "is-selected" : ""}`}
            type="button"
            aria-pressed={() => props.locale() === "en"}
            onClick={() => props.onLocaleChange("en")}
          >
            English
          </button>
        </div>
      </div>
      <div class="profile-choice">
        <span class="profile-choice-label">{() => copy().readerState}</span>
        <div class="segmented-control" role="group" aria-label={() => copy().readerState}>
          <For each={props.readerProfiles}>
            {(profile) => (
              <button
                class={() => `segment ${props.readerProfileId() === profile.id ? "is-selected" : ""}`}
                type="button"
                aria-pressed={() => props.readerProfileId() === profile.id}
                onClick={() => props.onReaderProfileChange(profile.id)}
              >
                {() => (props.locale() === "ja" ? profile.labelJa : profile.labelEn)}
              </button>
            )}
          </For>
        </div>
      </div>
      <div class="profile-choice">
        <span class="profile-choice-label">{() => copy().readingIntent}</span>
        <div class="segmented-control" role="group" aria-label={() => copy().readingIntent}>
          <For each={props.contentFilters}>
            {(filter) => (
              <button
                class={() => `segment ${props.contentFilterId() === filter.id ? "is-selected" : ""}`}
                type="button"
                aria-pressed={() => props.contentFilterId() === filter.id}
                onClick={() => props.onContentFilterChange(filter.id)}
              >
                {() => (props.locale() === "ja" ? filter.labelJa : filter.labelEn)}
              </button>
            )}
          </For>
        </div>
      </div>
    </div>
  );
}

function FoldSection(props: {
  node: FoldNode;
  locale: () => ReaderLocale;
  isCollapsed: () => boolean;
  onToggle: (id: string) => void;
}) {
  const sectionClass = createMemo(() =>
    `fold-section ${props.isCollapsed() ? "is-collapsed" : "is-expanded"}`,
  );
  const document = createMemo(() => parse(props.node.body));
  const copy = createMemo(() => viewerCopy[props.locale()]);
  const actionLabel = createMemo(
    () => `${props.node.title}: ${props.isCollapsed() ? copy().open : copy().close}`,
  );

  return (
    <article class={sectionClass} data-fold-id={props.node.id}>
      <header class="fold-heading">
        <button
          class="fold-toggle"
          type="button"
          aria-label={actionLabel}
          aria-expanded={() => !props.isCollapsed()}
          title={actionLabel}
          onClick={() => props.onToggle(props.node.id)}
        />
        <div class="fold-heading-copy">
          <div class="fold-meta">
            <span>{() => copy().kind[props.node.kind]}</span>
            <Show when={props.isCollapsed}>{() => <span>{() => copy().assumedKnown}</span>}</Show>
          </div>
          <h2>{props.node.title}</h2>
        </div>
      </header>
      <Show when={() => !props.isCollapsed()}>
        {() => (
          <div class="fold-body">
            <MarkdownRenderer ast={document()} />
            {props.node.requires && (
              <p class="fold-requires">
                {() => copy().prerequisite}: {props.node.requires.join(", ")}
              </p>
            )}
            {props.node.evidence && (
              <p class="fold-evidence">
                {() => copy().evidence}: {props.node.evidence.join(", ")}
              </p>
            )}
          </div>
        )}
      </Show>
    </article>
  );
}

function FolddownViewer() {
  const [locale, setLocale] = createSignal<ReaderLocale>("ja");
  const [background, setBackground] = createSignal<ProgrammingBackground>("typescript");
  const [readerProfileId, setReaderProfileId] = createSignal(moonbitReaderProfiles[0]!.id);
  const [contentFilterId, setContentFilterId] = createSignal(moonbitContentFilters[0]!.id);
  const [collapsed, setCollapsed] = createSignal<Record<string, boolean>>(
    createInitialCollapsedState(moonbitForProgrammersNodes, moonbitReaderProfiles[0]!),
  );
  const copy = createMemo(() => viewerCopy[locale()]);
  const visibleNodes = createMemo(() =>
    selectNodesForReader(
      moonbitForProgrammersNodes,
      {
        locale: locale(),
        roles: [PROGRAMMER_ROLES[background()]],
      },
      moonbitContentFilters.find((candidate) => candidate.id === contentFilterId())!,
    ),
  );

  const applyReaderProfile = (profileId: string) => {
    const profile = moonbitReaderProfiles.find((candidate) => candidate.id === profileId);
    if (profile === undefined) return;
    setReaderProfileId(profile.id);
    setCollapsed(createInitialCollapsedState(moonbitForProgrammersNodes, profile));
  };

  const applyContentFilter = (filterId: string) => {
    if (!moonbitContentFilters.some((candidate) => candidate.id === filterId)) return;
    setContentFilterId(filterId);
  };

  const toggleNode = (id: string) => {
    setCollapsed((current) => ({
      ...current,
      [id]: !(current[id] ?? false),
    }));
  };

  return (
    <div class="folddown-viewer">
      <header class="viewer-header">
        <p class="eyebrow">FOLDDOWN / ADAPTIVE READER</p>
        <h1>{() => copy().title[background()]}</h1>
      </header>

      <section class="profile-bar" aria-label="読者プロファイル">
        <div class="reader-profile">
          <ReaderAudienceControls
            locale={locale}
            background={background}
            readerProfileId={readerProfileId}
            readerProfiles={moonbitReaderProfiles}
            contentFilterId={contentFilterId}
            contentFilters={moonbitContentFilters}
            onLocaleChange={setLocale}
            onBackgroundChange={setBackground}
            onReaderProfileChange={applyReaderProfile}
            onContentFilterChange={applyContentFilter}
          />
        </div>
      </section>

      <main class="reader-document">
        <div class="document-title">
          <p>{() => copy().documentTitle}</p>
          <span>{() => copy().declarationCount(visibleNodes().length)}</span>
        </div>
        <For each={visibleNodes}>
          {(node) => (
            <FoldSection
              node={node}
              locale={locale}
              isCollapsed={() => collapsed()[node.id] ?? false}
              onToggle={toggleNode}
            />
          )}
        </For>
      </main>
    </div>
  );
}

render(document.getElementById("app")!, <FolddownViewer />);
