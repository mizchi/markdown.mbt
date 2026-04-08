///| Interactive MDX Notebook Types

///|

///| marimo-inspired reactive notebook system for MDX

// =============================================================================
// Cell Types
// =============================================================================

///|
/// A cell is a unit of executable code in the notebook
pub(all) struct Cell {
  /// Unique identifier for this cell
  id : String
  /// Source code of the cell
  source : String
  /// Language of the cell (moonbit, javascript, python, etc.)
  language : String
  /// Variables defined by this cell
  defines : Array[String]
  /// Variables exported by this cell (pub definitions in MoonBit)
  exports : Array[String]
  /// Variables referenced by this cell
  references : Array[String]
  /// Cell output after evaluation
  output : CellOutput?
  /// Cell state
  state : CellState
}

///|
/// Cell output types
pub(all) enum CellOutput {
  /// Plain text output
  Text(String)
  /// HTML output for rendering
  Html(String)
  /// JSON data for visualization
  Json(String)
  /// Error output
  Error(String)
  /// Multiple outputs
  Multi(Array[CellOutput])
}

///|
/// Cell execution state
pub(all) enum CellState {
  /// Not yet executed
  Idle
  /// Currently executing
  Running
  /// Successfully executed
  Success
  /// Execution failed
  Failed
  /// Stale (dependencies changed, needs re-run)
  Stale
}

// =============================================================================
// Dependency Graph
// =============================================================================

///|
/// Edge in the dependency graph
pub(all) struct DependencyEdge {
  /// Source cell ID (defines the variable)
  from : String
  /// Target cell ID (references the variable)
  to : String
  /// Variable name connecting them
  variable : String
}

///|
/// Dependency graph for reactive execution
pub(all) struct DependencyGraph {
  /// All cells in the notebook
  cells : Map[String, Cell]
  /// Edges representing dependencies
  edges : Array[DependencyEdge]
  /// Topologically sorted execution order
  mut execution_order : Array[String]
}

// =============================================================================
// Inline Directive
// =============================================================================

///|
/// Inline file inclusion directive
pub(all) struct InlineDirective {
  /// Source path (relative to current file)
  source : String
  /// Optional section selector (e.g., "#heading-id")
  section : String?
  /// Whether to recursively process inlines
  recursive : Bool
} derive(Eq, Debug)

// =============================================================================
// Code Block Attributes
// =============================================================================

///|
/// Extended code block attributes for notebooks
pub(all) struct CodeBlockAttrs {
  /// Cell identifier (:cell=name)
  cell : String?
  /// Dependencies (:deps=a,b,c)
  deps : Array[String]
  /// Whether to show the code (:hide)
  hidden : Bool
  /// Output format (:output=html|json|text)
  output_format : OutputFormat
  /// Whether this is an executable cell
  executable : Bool
}

///|
/// Output format for cell evaluation
pub(all) enum OutputFormat {
  Text
  Html
  Json
  Auto
} derive(Eq, Debug)

// =============================================================================
// Notebook
// =============================================================================

///|
/// A notebook document
pub(all) struct Notebook {
  /// Source file path
  path : String
  /// Parsed cells
  cells : Array[Cell]
  /// Dependency graph
  graph : DependencyGraph
  /// Inline directives found
  inlines : Array[InlineDirective]
  /// Frontmatter metadata
  frontmatter : Map[String, String]
}

// =============================================================================
// Evaluation Context
// =============================================================================

///|
/// Context for cell evaluation
pub(all) struct EvalContext {
  /// Available variables from executed cells
  variables : Map[String, String]
  /// Cell outputs by ID
  outputs : Map[String, CellOutput]
}

// =============================================================================
// Constructors
// =============================================================================

///|
pub fn Cell::new(id : String, source : String, language : String) -> Cell {
  {
    id,
    source,
    language,
    defines: [],
    exports: [],
    references: [],
    output: None,
    state: Idle,
  }
}

///|
pub fn DependencyGraph::new() -> DependencyGraph {
  { cells: {}, edges: [], execution_order: [] }
}

///|
pub fn CodeBlockAttrs::new() -> CodeBlockAttrs {
  {
    cell: None,
    deps: [],
    hidden: false,
    output_format: Auto,
    executable: false,
  }
}

///|
pub fn Notebook::new(path : String) -> Notebook {
  {
    path,
    cells: [],
    graph: DependencyGraph::new(),
    inlines: [],
    frontmatter: {},
  }
}

///|
pub fn EvalContext::new() -> EvalContext {
  { variables: {}, outputs: {} }
}

///|
pub fn InlineDirective::new(source : String) -> InlineDirective {
  { source, section: None, recursive: true }
}

pub impl Show for InlineDirective with output(
  self : InlineDirective,
  logger : &Logger,
) -> Unit {
  logger.write_string(@debug.to_string(self))
}

pub impl Show for OutputFormat with output(
  self : OutputFormat,
  logger : &Logger,
) -> Unit {
  logger.write_string(@debug.to_string(self))
}
