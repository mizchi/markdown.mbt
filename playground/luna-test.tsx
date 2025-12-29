import { createSignal, createEffect, render } from "@luna_ui/luna";
import { parse } from "../js/api.js";
import { MarkdownRenderer } from "./ast-renderer";

function TestApp() {
  const [text, setText] = createSignal("# Hello\n\nType here...");
  
  // Parse markdown reactively
  const getAst = () => parse(text());
  
  console.log("TestApp rendered once");
  
  // Debug effect
  createEffect(() => {
    console.log("Text changed:", text().slice(0, 30));
  });
  
  return (
    <div style={{ display: "flex", height: "100vh" }}>
      <div style={{ flex: 1, padding: "10px" }}>
        <textarea
          style={{ width: "100%", height: "100%", fontFamily: "monospace" }}
          value={text()}
          onInput={(e) => setText((e.target as HTMLTextAreaElement).value)}
        />
      </div>
      <div style={{ flex: 1, padding: "10px", overflow: "auto" }}>
        <MarkdownRenderer ast={getAst()} />
      </div>
    </div>
  );
}

render(document.getElementById("app")!, <TestApp />);
