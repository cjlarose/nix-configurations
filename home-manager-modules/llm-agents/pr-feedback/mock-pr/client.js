import { FileDiff } from "https://esm.sh/@pierre/diffs@1.2.10?bundle";
let diffStyle="unified";
const groups=[]; // {mount, files} -- the range diff plus one per commit
function esc(s){return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;").replace(/'/g,"&#x27;");}
function themeType(){const a=document.documentElement.getAttribute("data-theme");if(a==="dark")return"dark";if(a==="light")return"light";return matchMedia("(prefers-color-scheme: dark)").matches?"dark":"light";}
function shells(mount,files,empty){mount.innerHTML="";if(!files.length){mount.innerHTML=`<div class="empty">${empty}</div>`;return;}files.forEach((f)=>{const el=document.createElement("div");el.className="file";const label=({M:"changed",A:"added",D:"deleted",R:"renamed"})[f.status]||"changed";const cls=f.status==="D"?"pill del":"pill";el.innerHTML=`<div class="file-head"><span class="chev">▾</span><span class="file-path">${esc(f.path)}</span><span class="file-badges"><span class="adddel"><span class="a">+${f.additions}</span> <span class="d">−${f.deletions}</span></span><span class="${cls}">${label}</span></span></div><div class="file-body"><div class="diff-mount"></div></div>`;mount.appendChild(el);});mount.querySelectorAll(".file-head .chev").forEach(c=>c.addEventListener("click",()=>{c.closest(".file").querySelector(".file-body").classList.toggle("hidden");c.closest(".file-head").classList.toggle("collapsed");}));}
function renderGroup(g){const o={theme:{light:"github-light",dark:"github-dark"},themeType:themeType(),overflow:"wrap",diffStyle};const mounts=g.mount.querySelectorAll(".diff-mount");g.files.forEach((f,i)=>{const t=mounts[i];if(!t)return;t.innerHTML="";try{new FileDiff(o).render({containerWrapper:t,oldFile:{name:f.path,contents:f.old||""},newFile:{name:f.path,contents:f.new||""}});}catch(e){t.innerHTML=`<pre style="padding:12px;color:var(--danger-fg)">diff render failed: ${e}</pre>`;}});}
function renderAll(){groups.forEach(renderGroup);}
function addGroup(mount,files,empty){shells(mount,files,empty);groups.push({mount,files});}
function readJson(id){const el=document.getElementById(id);if(!el)return null;try{return JSON.parse(el.textContent);}catch(e){return null;}}
matchMedia("(prefers-color-scheme: dark)").addEventListener("change",renderAll);
new MutationObserver(renderAll).observe(document.documentElement,{attributes:true,attributeFilter:["data-theme"]});
document.querySelectorAll("#styleToggle button").forEach(b=>b.addEventListener("click",()=>{document.querySelectorAll("#styleToggle button").forEach(x=>x.classList.remove("active"));b.classList.add("active");diffStyle=b.getAttribute("data-style");renderAll();}));
document.querySelectorAll(".tab").forEach(tab=>tab.addEventListener("click",()=>{document.querySelectorAll(".tab").forEach(t=>t.classList.remove("active"));tab.classList.add("active");const t=document.querySelector(tab.getAttribute("data-target"));if(t)t.scrollIntoView({behavior:"smooth",block:"start"});}));
document.querySelectorAll(".body-toggle button").forEach(b=>b.addEventListener("click",()=>{const v=b.getAttribute("data-view");document.querySelectorAll(".body-toggle button").forEach(x=>x.classList.toggle("active",x===b));document.querySelectorAll(".body-view").forEach(el=>el.classList.toggle("hidden",el.getAttribute("data-view")!==v));}));
document.querySelectorAll(".cdiff-head").forEach(h=>h.addEventListener("click",()=>{h.classList.toggle("collapsed");const b=h.parentElement.querySelector(".cdiff-body");if(b)b.classList.toggle("hidden");}));
// Range diff (the "Files changed" tab).
const rangeMount=document.getElementById("files-mount");
const rangeFiles=readJson("diffdata");
if(rangeFiles===null){rangeMount.innerHTML=`<pre style="padding:12px;color:var(--danger-fg)">could not parse inlined diff data</pre>`;}
else{addGroup(rangeMount,rangeFiles,"No file changes in this range.");}
// Per-commit diffs (in the Commits tab).
document.querySelectorAll(".commit-files").forEach(mount=>{const i=mount.getAttribute("data-commit");const f=readJson("commitdiff-"+i);if(f===null){mount.innerHTML=`<pre style="padding:12px;color:var(--danger-fg)">could not parse commit diff data</pre>`;return;}addGroup(mount,f,"No file changes in this commit.");});
renderAll();
