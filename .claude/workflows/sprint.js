export const meta = {
  name: 'sprint',
  description: 'Exécute en parallèle les tâches prêtes du backlog, les fait vérifier par un QA indépendant, une passe de correction si besoin',
  whenToUse: 'Après `python tools/tasks/plan.py ready --out tasks/ready.json` : passer le JSON produit (objet avec `tasks`) en args.',
  phases: [
    { title: 'Build', detail: 'un agent par tâche, fichiers disjoints' },
    { title: 'Verify', detail: 'QA sceptique par tâche, sans modifier' },
    { title: 'Fix', detail: 'une passe de correction puis re-vérification' },
  ],
}

// Contrat : args = { tasks: [{ id, title, model, agent, isolation, files, prompt, verify_prompt }] }
// produit par tools/tasks/plan.py (le rendu des prompts vit en Python, ce script reste générique).
const tasks = (args && args.tasks) || []
if (!tasks.length) {
  log('Aucune tâche prête : rien à faire.')
  return { results: [] }
}
log(`Sprint : ${tasks.length} tâche(s) — ${tasks.map(t => t.id).join(', ')}`)

const IMPL = {
  type: 'object',
  properties: {
    done: { type: 'boolean', description: 'true si tous les critères d’acceptation sont remplis' },
    summary: { type: 'string' },
    files_changed: { type: 'array', items: { type: 'string' } },
    commands: { type: 'array', items: { type: 'string' }, description: 'commandes lancées et résultat' },
    blocked_on: { type: 'string', description: 'décision ou fichier hors périmètre nécessaire, sinon vide' },
  },
  required: ['done', 'summary', 'files_changed'],
}

const VERDICT = {
  type: 'object',
  properties: {
    pass: { type: 'boolean' },
    issues: { type: 'array', items: { type: 'string' }, description: 'un problème précis par entrée, avec fichier:ligne' },
    evidence: { type: 'string', description: 'commandes lancées et ce qu’elles ont montré' },
  },
  required: ['pass', 'issues', 'evidence'],
}

const opts = (t, phase, extra) => {
  const o = { label: `${phase.toLowerCase()}:${t.id}`, phase, schema: extra.schema }
  if (extra.model) o.model = extra.model
  if (extra.agentType) o.agentType = extra.agentType
  if (t.isolation === 'worktree' && phase !== 'Verify') o.isolation = 'worktree'
  return o
}

// Mode « brief » (plan.py ready --brief) : les prompts ne voyagent pas dans args,
// chaque agent lit lui-même son contrat depuis le planificateur.
const REPO = 'C:/Users/srko/Desktop/fps'
// Un message de l'utilisateur peut être relayé aux sous-agents pendant leur exécution : il
// s'adresse au lead, jamais à eux. Sans cette consigne, des agents ont répondu à la question
// au lieu de coder, et le QA a validé un rendu vide.
// args.handled = résumé du dernier message utilisateur, déjà traité par le lead : le nommer
// explicitement évite que l'agent y voie une consigne suspecte ou une demande qui lui revient.
// args.handled = { quote: message utilisateur mot pour mot, action: ce que le lead en fait }.
// Citer le message exact (et non une paraphrase) évite qu'un agent y voie une fausse citation.
const handled = (args && args.handled) || null
const FOCUS = 'Contexte du lead : l’utilisateur a demandé que le backlog du jeu soit exécuté en vagues ' +
  'd’agents parallèles ; tu es l’un de ces agents et ta tâche ci-dessous est cette demande légitime. ' +
  (handled && handled.quote
    ? `Son dernier message, mot pour mot : « ${handled.quote} ». Le lead le traite lui-même (${handled.action}) : ` +
      'il ne te concerne pas, n’y réponds pas. '
    : '') +
  'Si un message utilisateur te parvient pendant ton travail, il s’adresse au lead : poursuis ta tâche.'
const mission = t => `${FOCUS}\n\n` + (t.prompt ||
  `Ta mission est la tâche ${t.id} du backlog du dépôt ${REPO}. Commence par exécuter ` +
  `\`python tools/tasks/plan.py prompt ${t.id}\` depuis ${REPO} et suis ce contrat à la lettre : ` +
  `il fixe les seuls fichiers que tu peux modifier (${t.files.join(', ')}), les critères d'acceptation et la vérification.`)
const checkBrief = t => `${FOCUS}\n\n` + (t.verify_prompt ||
  `Exécute \`python tools/tasks/plan.py verify-prompt ${t.id}\` depuis ${REPO} : c'est ta consigne de vérification, applique-la.`) +
  '\nUn rendu sans aucun fichier modifié est un échec (pass=false).'

const build = (t, feedback) => {
  const base = mission(t)
  const prompt = feedback
    ? `${base}\n\n## Retour du vérificateur (à corriger)\n${feedback}\n\nCorrige uniquement ces points, dans tes fichiers.`
    : base
  return agent(prompt, opts(t, feedback ? 'Fix' : 'Build', { schema: IMPL, model: t.model, agentType: t.agent }))
}

const verify = (t, impl) =>
  agent(
    `${checkBrief(t)}\n\n## Rapport de l’agent\n${impl.summary}\nFichiers : ${(impl.files_changed || []).join(', ')}\n` +
      (impl.files_changed || [])
        .map(f => f.replace(/\\/g, '/').replace(/^.*?\/Desktop\/fps\//i, '').replace(/\.uid$/, ''))
        .filter(f => !t.files.some(o => f.startsWith(o.replace(/\*.*$/, '').replace(/\/$/, ''))))
        .map(f => `ATTENTION : ${f} est hors du périmètre déclaré.`).join('\n'),
    opts(t, 'Verify', { schema: VERDICT, model: 'sonnet', agentType: 'general-purpose' }),
  )

const results = await pipeline(
  tasks,
  t => build(t, null),
  async (impl, t) => {
    if (!impl) return { id: t.id, status: 'failed', reason: 'agent de build mort ou ignoré' }
    const changed = (impl.files_changed || []).length
    // Un agent qui a livré mais signale un point hors périmètre passe quand même par le QA :
    // le point est remonté au lead en note, la tâche n'est pas bloquée pour autant.
    if (impl.blocked_on && !changed) return { id: t.id, status: 'blocked', reason: impl.blocked_on, files: [], delivered: false }
    if (!changed) return { id: t.id, status: 'failed', reason: 'aucun fichier modifié', summary: impl.summary }
    const v = await verify(t, impl)
    return { id: t.id, impl, v }
  },
  async (r, t) => {
    if (!r || r.status) return r
    if (r.v && r.v.pass) return { id: t.id, status: 'done', summary: r.impl.summary, files: r.impl.files_changed, lead_note: r.impl.blocked_on || '' }
    const issues = r.v ? r.v.issues.join('\n- ') : 'vérification impossible'
    const fixed = await build(t, `- ${issues}`)
    if (!fixed) return { id: t.id, status: 'failed', reason: issues }
    const v2 = await verify(t, fixed)
    return v2 && v2.pass
      ? { id: t.id, status: 'done', summary: fixed.summary, files: fixed.files_changed, fixed_after_review: true }
      : { id: t.id, status: 'failed', reason: v2 ? v2.issues.join(' | ') : 'vérification impossible', files: fixed.files_changed }
  },
)

const clean = results.map((r, i) => r || { id: tasks[i].id, status: 'failed', reason: 'étape interrompue' })
const by = s => clean.filter(r => r.status === s).map(r => r.id)
log(`Terminé : ${by('done').length} faites, ${by('failed').length} en échec, ${by('blocked').length} bloquées`)
return {
  done: by('done'),
  failed: by('failed'),
  blocked: by('blocked'),
  next: `python tools/tasks/plan.py done ${by('done').join(' ')}`,
  results: clean,
}
