import{c as e,d as t,f as n,h as r,l as i,m as a,n as o,p as s,r as c,s as l,t as u,u as d}from"./jsx-runtime-CbumG8MQ.js";import{t as f}from"./SyntaxHighlightEditor-B4T4D3xh.js";import{n as p,r as m,t as h}from"./ast-renderer-_jVmtlou.js";var g=`/markdown.mbt/moonlight-editor.editor.js`,_=null;function v(){let e=window.__moonlightEditorModule;return e?Promise.resolve(e):(_||=new Promise((e,t)=>{let n=()=>{let n=window.__moonlightEditorModule;if(!n){_=null,t(Error(`Moonlight editor bundle loaded without module export`));return}e(n)},r=document.querySelector(`script[data-moonlight-editor="true"]`);if(r){r.addEventListener(`load`,n,{once:!0}),r.addEventListener(`error`,()=>{_=null,t(Error(`Failed to load Moonlight editor bundle`))},{once:!0});return}let i=document.createElement(`script`);i.type=`module`,i.src=g,i.dataset.moonlightEditor=`true`,i.addEventListener(`load`,n,{once:!0}),i.addEventListener(`error`,()=>{_=null,i.remove(),t(Error(`Failed to load Moonlight editor bundle`))},{once:!0}),document.head.appendChild(i)}),_)}function y(e){let{initialSvg:t,span:n,onSvgChange:i,width:a=400,height:c=300,readonly:d=!1,theme:f=`light`}=e,p=null,h=null,g=!1,_=!1,[y,b]=l(!1),[x,S]=l(!1),C=async()=>{if(!(!p||g)){g=!0,b(!1),S(!1);try{let e=m(t),{createEditor:r}=await v();if(!p||_){g=!1;return}p.innerHTML=``;let o=r(p,{width:a,height:c,theme:f,readonly:d,initialSvg:e});if(!o)throw g=!1,Error(`createEditor returned null/undefined`);if(h=o,!d&&i){let e=!0;h.onChange(()=>{if(e){e=!1;return}if(h&&!_){let e=h.exportSvg();i(e,n)}})}_||b(!0)}catch(e){console.error(`Failed to initialize MoonlightEditor:`,e),g=!1,_||S(!0)}}};return s(()=>{C()}),r(()=>{_=!0,h&&=(h.destroy(),null)}),o(`div`,{class:`moonlight-editor-wrapper`,"data-span":n,style:{width:`${a}px`,minHeight:`${c}px`},children:u(`div`,{ref:e=>{p=e},style:{width:`100%`,minHeight:`${c}px`},children:[!y()&&!x()&&o(`div`,{style:{width:`${a}px`,height:`${c}px`,border:`1px solid #e1e4e8`,borderRadius:`6px`,display:`flex`,alignItems:`center`,justifyContent:`center`,backgroundColor:`#f6f8fa`,color:`#586069`,fontSize:`14px`},children:`Loading Moonlight Editor...`}),x()&&u(`div`,{style:{width:`${a}px`,height:`${c}px`,border:`1px solid #f97583`,borderRadius:`6px`,display:`flex`,flexDirection:`column`,alignItems:`center`,justifyContent:`center`,backgroundColor:`#ffeef0`,color:`#d73a49`,fontSize:`14px`,gap:`8px`},children:[o(`span`,{children:`Failed to load Moonlight Editor`}),o(`button`,{onClick:()=>{C()},style:{padding:`4px 12px`,background:`#d73a49`,color:`white`,border:`none`,borderRadius:`4px`,cursor:`pointer`},children:`Retry`})]})]})})}function b(e){let t=i(()=>{let t=e.ast();return t?[{ast:t,dark:e.isDark()}]:[]});return o(`div`,{class:`preview`,ref:t=>{e.containerRef?.(t)},children:o(d,{each:t,children:t=>o(h,{ast:t.ast,callbacks:e.callbacks,options:{codeBlockHandlers:{svg:{render:(e,t,n,r)=>r===`code`?null:o(p,{"data-span":t,html:m(e)},n)},"moonlight-svg":{render:(n,r,i)=>o(y,{initialSvg:n,span:r,onSvgChange:e.onSvgChange,width:400,height:300,theme:t.dark?`dark`:`light`},i)}}}})})})}var x=`markdown-editor`,S=`documents`,C=`current`,w=`markdown-editor-ui`,ee=300,te=`# markdown.mbt Playground

A high-performance Markdown parser written in [MoonBit](https://www.moonbitlang.com/), compiled to WebAssembly.

## Features

- **Blazing Fast**: MoonBit compiles to efficient WASM for near-native performance
- **Syntax Highlighting**: Integrated code highlighting powered by Lezer
- **Live Preview**: Real-time Markdown rendering as you type
- **Auto Save**: Your content is automatically saved to browser storage (IndexedDB)

## Code Example

\`\`\`typescript
// Syntax highlighting works for multiple languages
function greet(name: string): string {
  return \`Hello, \${name}!\`;
}
\`\`\`

\`\`\`rust
fn main() {
    println!("Hello from Rust!");
}
\`\`\`

## Markdown Support

- **Bold** and *italic* text
- [Links](https://github.com/mizchi/markdown.mbt)
- \`inline code\`
- > Blockquotes

## SVG Preview

Edit the SVG below and see live preview:

\`\`\`svg
<svg width="200" height="100" xmlns="http://www.w3.org/2000/svg">
  <rect x="10" y="10" width="80" height="80" fill="#4a90d9" rx="8"/>
  <circle cx="150" cy="50" r="40" fill="#e74c3c"/>
  <text x="100" y="95" text-anchor="middle" fill="#333" font-size="12">Edit me!</text>
</svg>
\`\`\`

## Moonlight SVG Editor

Interactive SVG editing with [Moonlight](https://github.com/mizchi/moonlight):

\`\`\`moonlight-svg
<svg viewBox="0 0 400 300" xmlns="http://www.w3.org/2000/svg">
  <rect x="50" y="50" width="120" height="80" fill="#3498db" rx="10"/>
  <circle cx="280" cy="90" r="50" fill="#e74c3c"/>
  <polygon points="200,200 150,280 250,280" fill="#2ecc71"/>
</svg>
\`\`\`

## Interactive Task List

Click the checkboxes below - they update the source in real-time!

- [ ] Try clicking this checkbox
- [x] This one is already checked
- [ ] Interactive editing from preview

---

Source: [github.com/mizchi/markdown.mbt](https://github.com/mizchi/markdown.mbt)
`;function T(){return new Promise((e,t)=>{let n=indexedDB.open(x,1);n.onerror=()=>t(n.error),n.onsuccess=()=>e(n.result),n.onupgradeneeded=()=>{let e=n.result;e.objectStoreNames.contains(S)||e.createObjectStore(S)}})}async function ne(e){let t=await T(),n=Date.now();return new Promise((r,i)=>{let a=t.transaction(S,`readwrite`),o=a.objectStore(S).put({content:e,timestamp:n},C);o.onerror=()=>i(o.error),o.onsuccess=()=>r(n),a.oncomplete=()=>t.close()})}async function E(){try{let e=await T();return new Promise((t,n)=>{let r=e.transaction(S,`readonly`),i=r.objectStore(S).get(C);i.onerror=()=>n(i.error),i.onsuccess=()=>t(i.result||null),r.oncomplete=()=>e.close()})}catch{return null}}function D(){return window.innerWidth<768||/Android|iPhone|iPad|iPod/i.test(navigator.userAgent)}function O(){let e=D();try{let t=localStorage.getItem(w);if(t){let n=JSON.parse(t);return{viewMode:e&&n.viewMode===`split`?`editor`:n.viewMode||(e?`editor`:`split`),editorMode:n.editorMode||(e?`simple`:`highlight`),cursorPosition:n.cursorPosition||0}}}catch{}return{viewMode:e?`editor`:`split`,editorMode:e?`simple`:`highlight`,cursorPosition:0}}function k(e){try{let t={...O(),...e};localStorage.setItem(w,JSON.stringify(t))}catch{}}function re(e,t){for(let n=0;n<e.children.length;n++){let r=e.children[n],i=r.position?.start?.offset??0,a=r.position?.end?.offset??0;if(t>=i&&t<=a)return n}let n=e.children[e.children.length-1],r=n?.position?.end?.offset??0;return e.children.length>0&&n&&t>=r?e.children.length-1:null}function ie(t){let n=null,r=e=>{n=e,e.value=t.value(),t.ref?.(e)};e(()=>{let e=t.value();n&&n.value!==e&&(n.value=e)});let i=e=>{let n=e.target;t.onChange(n.value),t.onCursorChange?.(n.selectionStart)},a=e=>{let n=e.target;t.onCursorChange?.(n.selectionStart)};return o(`textarea`,{ref:e=>r(e),class:`simple-editor`,onInput:i,onKeyUp:a,onClick:a,spellcheck:!1})}function A(e){return o(`span`,{dangerouslySetInnerHTML:{__html:e.svg},style:{display:`flex`,alignItems:`center`}})}var ae=`<svg viewBox="0 0 20 20" width="18" height="18" fill="currentColor">
  <rect x="1" y="2" width="8" height="16" rx="1" stroke="currentColor" stroke-width="1.5" fill="none"/>
  <rect x="11" y="2" width="8" height="16" rx="1" stroke="currentColor" stroke-width="1.5" fill="none"/>
</svg>`,oe=`<svg viewBox="0 0 20 20" width="18" height="18" fill="currentColor">
  <rect x="2" y="2" width="16" height="16" rx="1" stroke="currentColor" stroke-width="1.5" fill="none"/>
  <line x1="5" y1="6" x2="15" y2="6" stroke="currentColor" stroke-width="1.5"/>
  <line x1="5" y1="10" x2="12" y2="10" stroke="currentColor" stroke-width="1.5"/>
  <line x1="5" y1="14" x2="14" y2="14" stroke="currentColor" stroke-width="1.5"/>
</svg>`,se=`<svg viewBox="0 0 20 20" width="18" height="18" fill="currentColor">
  <rect x="2" y="2" width="16" height="16" rx="1" stroke="currentColor" stroke-width="1.5" fill="none"/>
  <circle cx="10" cy="10" r="3" stroke="currentColor" stroke-width="1.5" fill="none"/>
  <path d="M4 10 Q7 5, 10 5 Q13 5, 16 10 Q13 15, 10 15 Q7 15, 4 10" stroke="currentColor" stroke-width="1.5" fill="none"/>
</svg>`,j=`<svg viewBox="0 0 20 20" width="18" height="18" fill="none">
  <text x="2" y="14" font-size="12" fill="#d73a49" font-family="monospace" font-weight="bold">&lt;</text>
  <text x="8" y="14" font-size="12" fill="#22863a" font-family="monospace">/</text>
  <text x="12" y="14" font-size="12" fill="#0366d6" font-family="monospace" font-weight="bold">&gt;</text>
</svg>`,ce=`<svg viewBox="0 0 20 20" width="18" height="18" fill="currentColor">
  <rect x="2" y="2" width="16" height="16" rx="1" stroke="currentColor" stroke-width="1.5" fill="none"/>
  <line x1="5" y1="6" x2="15" y2="6" stroke="currentColor" stroke-width="1" opacity="0.5"/>
  <line x1="5" y1="9" x2="13" y2="9" stroke="currentColor" stroke-width="1" opacity="0.5"/>
  <line x1="5" y1="12" x2="14" y2="12" stroke="currentColor" stroke-width="1" opacity="0.5"/>
  <line x1="5" y1="15" x2="10" y2="15" stroke="currentColor" stroke-width="1" opacity="0.5"/>
</svg>`,M=`<svg viewBox="0 0 16 16" width="20" height="20" fill="currentColor">
  <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/>
</svg>`;function N(){let a=O(),d=D(),[p,m]=l(``),[h,g]=l(null),[_,v]=l(a.cursorPosition),[y,x]=l(!1),[S,C]=l((()=>{let e=localStorage.getItem(`theme`);return e?e===`dark`:window.matchMedia(`(prefers-color-scheme: dark)`).matches})()),[w,T]=l(`idle`),[N,le]=l(a.viewMode),[P,ue]=l(a.editorMode),de=i(()=>`container view-${N()} editor-mode-${P()}`),fe=i(()=>`view-mode-btn ${N()===`split`?`active`:``}`),pe=i(()=>`view-mode-btn ${N()===`editor`?`active`:``}`),me=i(()=>`view-mode-btn ${N()===`preview`?`active`:``}`),F=i(()=>`view-mode-btn ${P()===`highlight`?`active`:``}`),I=i(()=>`view-mode-btn ${P()===`simple`?`active`:``}`),L=i(()=>`save-status ${w()}`),R=null,z=null,B=null,V=!1,H=0,U=!1,[he,ge]=l(``),W;e(()=>{let e=p();clearTimeout(W),W=window.setTimeout(()=>{ge(e)},ee)});let _e=()=>{C(e=>!e)};e(()=>{let e=S();document.documentElement.setAttribute(`data-theme`,e?`dark`:`light`),localStorage.setItem(`theme`,e?`dark`:`light`)});let G=e=>{le(e),k({viewMode:e})},K=e=>{let t=P();if(t===e)return;let n=0,r=0;t===`highlight`&&R?(n=R.getCursorPosition(),r=R.getScrollTop()):t===`simple`&&z&&(n=z.selectionStart,r=z.scrollTop),ue(e),k({editorMode:e}),requestAnimationFrame(()=>{e===`highlight`&&R?(R.setCursorPosition(n),R.setScrollTop(r)):e===`simple`&&z&&(z.setSelectionRange(n,n),z.scrollTop=r,z.focus()),v(n)})};s(()=>{let e=e=>{(e.ctrlKey||e.metaKey)&&(e.key===`1`?(e.preventDefault(),G(`split`)):e.key===`2`?(e.preventDefault(),G(`editor`)):e.key===`3`&&(e.preventDefault(),G(`preview`)))};window.addEventListener(`keydown`,e),r(()=>{window.removeEventListener(`keydown`,e)})}),s(()=>{(async()=>{let e=te,t=0;try{let n=await E();n&&n.content&&(e=n.content,t=n.timestamp)}catch{}let r=c(e);n(()=>{m(e),g(r),x(!0)}),H=t,requestAnimationFrame(()=>{R?.focus()})})()}),s(()=>{async function e(){if(document.visibilityState===`visible`&&!(U||V))try{let e=await E();if(!e)return;e.timestamp>H&&(m(e.content),H=e.timestamp)}catch(e){console.error(`Failed to sync from IndexedDB:`,e)}}document.addEventListener(`visibilitychange`,e),r(()=>{document.removeEventListener(`visibilitychange`,e)})}),e(()=>{let e=he();y()&&V&&(U=!0,T(`saving`),ne(e).then(e=>{H=e,V=!1,U=!1,T(`saved`),setTimeout(()=>T(`idle`),1e3)}).catch(e=>{console.error(`Failed to save to IndexedDB:`,e),U=!1,T(`idle`)}))});let q=null,J=(e,t)=>{let[n=`0`,r=`0`]=e.split(`-`),i=parseInt(n,10),a=parseInt(r,10),o=p(),s=o.slice(i,a),l=t?s.replace(/\[ \]/,`[x]`):s.replace(/\[x\]/i,`[ ]`),u=o.slice(0,i)+l+o.slice(a);V=!0,m(u),g(c(u)),P()===`highlight`&&R?R.setValue(u,{start:i,end:a}):z&&(z.value=u),requestAnimationFrame(()=>{let e=u.indexOf(`[`,i);e!==-1&&(v(e),P()===`highlight`&&R?(R.setCursorPosition(e),R.focus()):z&&(z.setSelectionRange(e,e),z.focus()))})},ve=(e,t)=>{let[n=`0`,r=`0`]=t.split(`-`),i=parseInt(n,10),a=parseInt(r,10),o=p(),s=o.slice(i,a),c=s.indexOf(`
`)+1,l=s.lastIndexOf("\n```");if(c>0&&l>c){let t=o.slice(0,i+c),n=o.slice(i+l),r=t+e+n;V=!0,m(r),P()===`highlight`&&R?R.setValue(r):z&&(z.value=r)}},ye={onTaskToggle:J};e(()=>{let e=h();e&&(q=e)});let Y;e(()=>{let e=_(),t=h();!B||!t||(clearTimeout(Y),Y=window.setTimeout(()=>{requestAnimationFrame(()=>{if(!B||!q)return;let t=re(q,e);if(t===null)return;let n=q.children[t],r=`[data-span="${n.position?.start?.offset??0}-${n.position?.end?.offset??0}"]`,i=B.querySelector(r);i&&i.scrollIntoView({behavior:`smooth`,block:`center`})})},150))});let X,Z=e=>{V=!0,m(e),clearTimeout(X),X=window.setTimeout(()=>{g(c(e))},100)},Q,$=e=>{v(e),clearTimeout(Q),Q=window.setTimeout(()=>{k({cursorPosition:e})},500)};return o(t,{when:y,children:()=>u(`div`,{class:`app-container`,children:[u(`header`,{class:`toolbar`,children:[u(`div`,{class:`toolbar-left`,children:[u(`div`,{class:`view-mode-buttons`,children:[!d&&o(`button`,{class:fe,onClick:()=>G(`split`),title:`Split view (Ctrl+1)`,children:o(A,{svg:ae})}),o(`button`,{class:pe,onClick:()=>G(`editor`),title:`Editor only (Ctrl+2)`,children:o(A,{svg:oe})}),o(`button`,{class:me,onClick:()=>G(`preview`),title:`Preview only (Ctrl+3)`,children:o(A,{svg:se})})]}),u(`div`,{class:`editor-mode-buttons`,children:[o(`button`,{class:F,onClick:()=>K(`highlight`),title:`Syntax highlight editor`,children:o(A,{svg:j})}),o(`button`,{class:I,onClick:()=>K(`simple`),title:`Simple text editor`,children:o(A,{svg:ce})})]}),u(`span`,{class:L,children:[w()===`saving`&&`Saving...`,w()===`saved`&&`Saved`]})]}),u(`div`,{class:`toolbar-actions`,children:[o(`button`,{onClick:_e,class:`theme-toggle`,title:`Toggle dark mode`,children:S()?`☀️`:`🌙`}),o(`a`,{href:`https://github.com/mizchi/markdown.mbt`,target:`_blank`,rel:`noopener noreferrer`,class:`github-link`,title:`View on GitHub`,children:o(A,{svg:M})})]})]}),u(`div`,{class:de,children:[u(`div`,{class:`editor`,children:[o(`div`,{class:`editor-highlight-wrapper`,children:o(f,{ref:e=>{R=e},value:()=>p(),onChange:Z,onCursorChange:$,initialCursorPosition:a.cursorPosition})}),o(`div`,{class:`editor-simple-wrapper`,children:o(ie,{value:()=>p(),onChange:Z,onCursorChange:$,ref:e=>{z=e}})})]}),o(b,{ast:h,isDark:S,callbacks:ye,onSvgChange:ve,containerRef:e=>{B=e}})]})]})})}a(document.getElementById(`app`),o(N,{}));