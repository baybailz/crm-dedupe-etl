/* Slides for this scenario. Each slide: {id, kicker, render(), after?}.
   S exposes the shell helpers, the live data (S.D) and the config (S.CFG).

   Two slides carry a V1/V2 toggle: V1 is the project as it stood before this
   request, published by scripts/scenario.py as docs/data/v1.json. The shell
   knows nothing about it, so the deck fetches that file itself. */
'use strict';
const m = t => `<span class="mono">${t}</span>`;
const fileLang = p => p.endsWith('.yml') ? 'yml' : p.endsWith('.py') ? 'py'
  : p.endsWith('.csv') ? 'csv' : 'sql';

let V1 = null, ver = 'v2', v1Pick = 'models/stage/stg_company.sql';
fetch(`data/v1.json?t=${Date.now()}`, {cache: 'no-store'})
  .then(r => r.ok ? r.json() : null).then(d => {V1 = d; S.render();}).catch(() => {});

const v1Paths = () => new Set((V1?.files || []).map(f => f.path));
const v1Nodes = () => new Set((V1?.nodes || []).map(n => n.id));
const isV1 = () => ver === 'v1' && V1;
const verToggle = () => V1 ? `<div class="vtog">${['v1', 'v2'].map(v =>
  `<button class="vbtn${ver === v ? ' on' : ''}" data-ver="${v}">${v.toUpperCase()}</button>`).join('')}</div>` : '';
function wireVer(){
  document.querySelectorAll('[data-ver]').forEach(b => b.onclick = () => {
    if (ver === b.dataset.ver) return;
    ver = b.dataset.ver; S.render();
  });
}

/* ---- V1 code browser. V1 is a shape the project used to have, not a state
   the warehouse was ever in, so there are no rows to play behind it. ---- */
function v1Tree(files, cur){
  const root = {};
  files.forEach(f => {const parts = f.path.split('/'); let n = root;
    parts.forEach((p, i) => {if (i === parts.length - 1) (n.__files ??= []).push(f); else n = (n[p] ??= {});});});
  const ORDER = {macros:0, models:1, tests:2, seeds:3, scripts:4, stage:0, transform:1, conformed:2, datamart:3};
  const rec = (node, depth) => {
    let h = '';
    Object.keys(node).filter(k => k !== '__files')
      .sort((a, b) => (ORDER[a] ?? 9) - (ORDER[b] ?? 9) || a.localeCompare(b))
      .forEach(k => {h += `<div class="fxrow dir" style="padding-left:${8 + depth * 14}px">▾ ${S.esc(k)}</div>` + rec(node[k], depth + 1);});
    (node.__files || []).forEach(f => {const nm = f.path.split('/').pop();
      h += `<button class="fxrow${f.path === cur ? ' on' : ''}" data-v1open="${S.esc(f.path)}"
        style="padding-left:${8 + depth * 14}px"><span class="fico ${fileLang(nm)}"></span><span class="fname">${S.esc(nm)}</span></button>`;});
    return h;
  };
  return rec(root, 0);
}
function v1Ide(){
  const files = V1.files, cur = files.find(f => f.path === v1Pick) || files[0];
  const explorer = S.isNarrow()
    ? `<select class="fxsel" id="v1sel" aria-label="Choose a file">${files.map(f =>
        `<option value="${S.esc(f.path)}"${f.path === cur.path ? ' selected' : ''}>${S.esc(f.path)}</option>`).join('')}</select>`
    : `<aside class="fx"><div class="fxhead">EXPLORER</div><div class="fxrepo">${S.esc(S.CFG.repo.split('/')[1])}</div>
       <div class="fxbody">${v1Tree(files, cur.path)}</div></aside>`;
  return `<div class="ide tall">${explorer}
    ${S.codePanel(S.isNarrow() ? cur.path.split('/').pop() : cur.path,
      `${cur.sql.split('\n').length} lines`, cur.sql, fileLang(cur.path), 0)}</div>`;
}
function wireV1(){
  document.querySelectorAll('[data-v1open]').forEach(b => b.onclick = () => {v1Pick = b.dataset.v1open; S.render();});
  const sel = document.getElementById('v1sel');
  if (sel) sel.onchange = () => {v1Pick = sel.value; S.render();};
}
// V2: mark every file the request added. Cheap: the shell renders the tree,
// the deck decorates the rows that are not in V1.
function markAddedFiles(){
  const v1 = v1Paths();
  if (!v1.size || isV1()) return;
  document.querySelectorAll('.fx [data-open]').forEach(b => {
    if (v1.has(b.dataset.open)) return;
    b.classList.add('added');
    b.insertAdjacentHTML('beforeend', '<span class="newdot" title="added for this request">+</span>');
  });
  document.querySelectorAll('#fxsel option').forEach(o => {
    if (!v1.has(o.value)) o.textContent += '  +';
  });
}

/* ---- lineage ---- */
const SW = {seed:'seed', stage:'stg', transform:'int', conformed:'dim', datamart:'dm'};
const legend = (layers, added) => `<div class="legend">${layers.map(l =>
  `<span><span class="sw ${SW[l] || 'int'}"></span>${l}</span>`).join('')}${
  added ? '<span><span class="sw addsw"></span>added for this request</span>' : ''}</div>`;
const layersOf = nodes => (S.D.lineage?.layers || Object.keys(SW))
  .filter(l => nodes.some(n => n.layer === l));
const NODE_CLS = {seed:'n-seed', stage:'n-stg', transform:'n-int', conformed:'n-dim', datamart:'n-dm'};
const NODE_TAG = {seed:'SEED', stage:'STG', transform:'TRN', conformed:'DIM', datamart:'DM'};
function v1Dag(){
  if (S.isNarrow()) {
    return `<div class="vflow">${V1.nodes.map((n, i) => `${i ? '<div class="varrow"></div>' : ''}
      <div class="vlayer"><div class="vtag">${n.layer}</div>
      <div class="vnode ${NODE_CLS[n.layer]}">${n.id}</div></div>`).join('')}</div>`;
  }
  const node = (n, x) => `<rect class="dagnode ${NODE_CLS[n.layer]}"
      x="${x}" y="52" width="196" height="46" rx="10"/>
    <text class="dagtag" x="${x + 184}" y="68" text-anchor="end">${NODE_TAG[n.layer]}</text>
    <text class="dagtext" x="${x + 14}" y="84">${n.id}</text>`;
  const xs = [60, 432, 804];
  return `<svg viewBox="0 0 1060 150" role="img" aria-label="dbt lineage before this change">
    ${V1.nodes.map((n, i) => node(n, xs[i])).join('')}
    <path class="dagline" d="M256 75 H426"/><path class="dagline" d="M628 75 H798"/></svg>`;
}
function markAddedDag(){
  const v1 = v1Nodes();
  if (!v1.size || isV1()) return;
  document.querySelectorAll('.diagram text.dagtext').forEach(t => {
    if (v1.has(t.textContent)) return;
    const rect = t.previousElementSibling?.previousElementSibling;
    if (rect && rect.classList.contains('dagnode')) rect.classList.add('added');
  });
  document.querySelectorAll('.diagram .vnode').forEach(n => {
    if (!v1.has(n.textContent)) n.classList.add('added');
  });
}

window.SLIDES = [
  {id:'title', kicker:'BI · ETL SCENARIO', render(){
    return `<div class="titleslide">
      <div class="kicker">Scenario walkthrough</div>
      <h2>Import company lists.<br>Create zero duplicates.</h2>
      <div class="stackchips">
        <span class="schip hot">python</span><span class="schip hot">dbt</span>
        <span class="schip">duckdb</span><span class="schip">github actions</span>
        <span class="schip">jaro-winkler</span>
      </div>
      <p class="lead">The database already has companies in it. Sales bought company lists where one
        company arrives as 7-Eleven, 711, and 7-Eleven, Inc., with the address written three
        different ways. This pipeline works out which rows are already there, imports the ones
        that are not, and records what happened to every row.</p>
      <div class="byline">${S.esc(S.CFG.author)}</div>
    </div>`;}},

  {id:'assumptions', kicker:'ASSUMPTIONS & STRATEGY', render(){
    return `<h2>Assumptions &amp; strategy</h2>
      <div class="ptsec">What I assumed</div>
      <ul class="pointlist">
        <li><span class="pt">1</span><span><b>Master data is the source of truth.</b>
          ${m('crm_company')} wins every conflict. An import adds rows; it never edits or
          deletes one.</span></li>
        <li><span class="pt">2</span><span><b>Purchased data is low-trust.</b> Abbreviations,
          legal suffixes, missing zips, and duplicates inside the file itself.</span></li>
        <li><span class="pt">3</span><span><b>Identity is name and address.</b> Not name alone:
          the same name at a different street number is a second location.</span></li>
        <li><span class="pt">4</span><span><b>The team already runs dbt.</b> So this is a pull
          request to their project, in their conventions, not a new tool to adopt.</span></li>
        <li><span class="pt">5</span><span><b>Seeds stand in for a landing stage.</b> On a CDW the
          seed becomes a stage, and the loader becomes the copy into it.</span></li>
      </ul>
      <div class="ptsec">How I built it</div>
      <ul class="pointlist">
        <li><span class="pt">1</span><span><b>Narrow approach for efficiency.</b> I only compare
          records if they already share attributes. Jaro-Winkler scores name and address from
          there. No cross joins.</span></li>
        <li><span class="pt">2</span><span><b>Medallion layering.</b> raw → stage (normalize)
          → transform (match) → conformed (publish) → datamart, with tests at every layer.</span></li>
        <li><span class="pt">3</span><span><b>Re-running is safe.</b> ${m('dim_company')} is
          incremental on ${m('company_id')}, so loading the same file twice changes
          nothing.</span></li>
        <li><span class="pt">4</span><span><b>Built to be maintained.</b> Contracts sit beside
          the models they govern and settings are declared per layer. Adding a blocking key is
          one line; a steward owns the alias list in a spreadsheet.</span></li>
      </ul>`;}},

  {id:'arch', kicker:'THE ARCHITECTURE', render(){
    return `<h2>The architecture</h2>
      <p class="lead">Load dispatches a GitHub Actions workflow: Python ingest, dbt build,
        results committed back as JSON. A real pipeline, driven from a web page.</p>
      <div class="diagram" style="position:relative">
        ${S.isNarrow() ? S.archFlow() : S.svgArch()}
        ${S.isNarrow() ? '' : `<button class="zoombtn" id="archZoomBtn">${
          S.archZoom ? '&#8854; full picture' : '&#8853; zoom to pipeline'}</button>`}
      </div>`;}},

  {id:'lineage', kicker:'DBT LINEAGE', render(){
    const v1 = isV1();
    const nodes = v1 ? V1.nodes : (S.D.lineage?.nodes || []);
    return `<div class="h2row"><h2>dbt lineage</h2>${verToggle()}</div>
      <p class="lead">${v1
        ? `The project before this request. One stage view over the CRM, one dimension
           built from it. Nothing here knows about purchased data.`
        : `Two seeds, one stage model, the whole transform layer, three dimensions and a
           datamart are new. ${m('stg_company')} and ${m('dim_company')} already existed
           and were extended. Read from the dbt manifest after the last build, so the
           picture can never drift from the project.`}</p>
      <div class="diagram" style="margin:38px 0 26px">${
        v1 ? v1Dag() : (S.isNarrow() ? S.dagFlow() : S.svgDag())}</div>
      ${legend(layersOf(nodes), !v1)}`;},
   after(){wireVer(); markAddedDag();}},

  {id:'code', kicker:'THE CODE', render(){
    const files = S.D.models?.files || [];
    if (!files.length) {
      return `<h2>The code</h2>
        <p class="lead">Not published yet. It lands with the next pipeline run
          (${m('docs/data/models.json')}).</p>`;
    }
    const v1 = isV1(), shown = v1 ? V1.files : files;
    const lines = shown.reduce((a, f) => a + f.sql.split('\n').length, 0);
    const added = files.length - v1Paths().size;
    return `<div class="h2row"><h2>The code</h2>${verToggle()}</div>
      <p class="lead">${shown.length} files, ~${Math.round(lines / 10) * 10} lines.
        ${v1 ? 'The project before this request.'
             : `<span class="dim">${added} are new, marked
                <span class="newdot inline">+</span>. Three of those are the deliverables,
                the rest builds them.</span> Press ▶ on a model to see its rows from the
                last run.`}</p>
      ${v1 ? v1Ide() : S.ideHtml()}`;},
   after(){wireVer(); wireV1(); markAddedFiles();}},

  {id:'table', kicker:'THE RESULT', render(){
    const rows = [...(S.D.tables.dim_company || [])]
      .sort((a, b) => a.company_id - b.company_id).map(c => `
      <tr${c.source !== 'crm_company' ? ' class="rowimp"' : ''}>
        <td class="num mono faded">${S.esc(c.company_id)}</td>
        <td><b>${S.esc(c.company_name)}</b></td>
        <td>${S.esc(c.address)}<span class="sub2">${S.esc(c.city)}, ${S.esc(c.state)} ${S.esc(c.zip ?? '')}</span></td>
        <td><span class="mono faded">${S.esc(c.source)}</span>
          ${c.source_record_key ? `<span class="sub2 mono">${S.esc(c.source_record_key)}</span>` : ''}</td>
      </tr>`).join('');
    return `<h2>The result</h2>
      <p class="lead">${m('select * from dim_company')}</p>
      <div class="verdicts scrollbox"><table>
        <thead><tr><th>ID</th><th>Company</th><th>Address</th><th>Source</th></tr></thead>
        <tbody>${rows}</tbody></table></div>`;}},

  {id:'avoided', kicker:'WHAT WE AVOIDED', render(){
    const rank = r => r.source === 'crm_company' ? 0 : 1;
    const rows = [...(S.D.tables.dm_naive_import || [])]
      .sort((a, b) => String(a.cluster_key).localeCompare(String(b.cluster_key))
        || rank(a) - rank(b) || String(a.source).localeCompare(String(b.source)))
      .map(r => `
      <tr${r.in_cluster ? ' class="rowdup"' : ''}>
        <td><b>${S.esc(r.company_name)}</b></td>
        <td>${S.esc(r.address)}<span class="sub2">${S.esc(r.city)}, ${S.esc(r.state)} ${S.esc(r.zip ?? '')}</span></td>
        <td class="mono faded">${S.esc(r.phone_number ?? '—')}</td>
        <td><span class="mono faded">${S.esc(r.source)}</span></td>
      </tr>`).join('');
    return `<h2>What we avoided</h2>
      <p class="lead">${m('select * from dm_naive_import')} — the same rows imported blind,
        with no matching in between.</p>
      <div class="verdicts scrollbox"><table>
        <thead><tr><th>Company</th><th>Address</th><th>Phone</th><th>Source</th></tr></thead>
        <tbody>${rows}</tbody></table></div>`;}},
];
