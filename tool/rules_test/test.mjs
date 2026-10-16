// Checks firestore.rules against the exact shapes of the app's writes.
// Run: cd tool/rules_test && npm install && npm test   (needs Java)
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, deleteDoc, getDoc, getDocs, updateDoc, writeBatch, collection, query, where, arrayUnion, arrayRemove, deleteField } from 'firebase/firestore';
import fs from 'fs';
const env = await initializeTestEnvironment({ projectId: 'demo-tf', firestore: { rules: fs.readFileSync('../../firestore.rules','utf8'), host:'127.0.0.1', port:8085 } });
const me = env.authenticatedContext('u1').firestore();
const other = env.authenticatedContext('u2').firestore();
const anon = env.unauthenticatedContext().firestore();
const now = Date.now();
const task = { id:'t1', title:'Design', description:'', category_id:'c1', project_id:null, assignee_id:null, priority:2, status:'pending', start_at:now, end_at:now+3600000, completed_at:null, created_at:now, updated_at:now, deleted_at:null, is_synced:0,
  checklist:[{id:'k1',task_id:'t1',title:'a',is_done:1,sort_order:0,created_at:now,updated_at:now,deleted_at:null,is_synced:0}] };
const cat = { id:'c1', name:'Work', color:4280250347, created_at:now, updated_at:now, deleted_at:null, is_synced:0 };
const mem = { id:'m1', name:'Ali', created_at:now, updated_at:now, deleted_at:null, is_synced:0 };
const notif = { id:'n1', type:'task', kind:'reminder', title:'Reminder', body:'x', task_id:'t1', created_at:now, read_at:null };
let ok=0, bad=0;
async function t(name, p){ try{ await p; ok++; console.log('PASS', name);}catch(e){ bad++; console.log('FAIL', name, e.message);} }
const d=(db,p)=>doc(db,p);
await t('profile create', assertSucceeds(setDoc(d(me,'users/u1'), {name:'A', email:'a@b.c', created_at:now}, {merge:true})));
await t('profile name merge', assertSucceeds(setDoc(d(me,'users/u1'), {name:'B'}, {merge:true})));
await t('profile prefs', assertSucceeds(setDoc(d(me,'users/u1'), {title:'CEO', reminder_minutes:30, team_alerts:false, last_backup_at:now}, {merge:true})));
await t('profile bad prefs denied', assertFails(setDoc(d(me,'users/u1'), {team_alerts:'yes'}, {merge:true})));
await t('profile long title denied', assertFails(setDoc(d(me,'users/u1'), {title:'x'.repeat(200)}, {merge:true})));
await t('task', assertSucceeds(setDoc(d(me,'users/u1/tasks/t1'), task)));
await t('task completed', assertSucceeds(setDoc(d(me,'users/u1/tasks/t1'), {...task, status:'completed', completed_at:now})));
await t('category', assertSucceeds(setDoc(d(me,'users/u1/categories/c1'), cat)));
await t('project', assertSucceeds(setDoc(d(me,'users/u1/projects/p1'), {...cat, id:'p1'})));
await t('member', assertSucceeds(setDoc(d(me,'users/u1/members/m1'), mem)));
await t('notification', assertSucceeds(setDoc(d(me,'users/u1/notifications/n1'), notif)));
await t('mark read merge', assertSucceeds(setDoc(d(me,'users/u1/notifications/n1'), {read_at:now}, {merge:true})));
await t('old backup task (extra fields, no checklist)', assertSucceeds(setDoc(d(me,'users/u1/tasks/t9'), (({checklist,...r})=>({...r,id:'t9',user_id:'old'}))(task))));
await t('read own', assertSucceeds(getDoc(d(me,'users/u1/tasks/t1'))));
await t('delete own', assertSucceeds(deleteDoc(d(me,'users/u1/members/m1'))));
await t('other user read denied', assertFails(getDoc(d(other,'users/u1/tasks/t1'))));
await t('other user write denied', assertFails(setDoc(d(other,'users/u1/tasks/t2'), {...task,id:'t2'})));
await t('signed out denied', assertFails(getDoc(d(anon,'users/u1/tasks/t1'))));
await t('unknown collection denied', assertFails(setDoc(d(me,'users/u1/junk/x'), {id:'x', created_at:now})));
await t('id mismatch denied', assertFails(setDoc(d(me,'users/u1/tasks/zzz'), task)));
await t('bad status denied', assertFails(setDoc(d(me,'users/u1/tasks/t1'), {...task, status:'weird'})));
await t('title string required', assertFails(setDoc(d(me,'users/u1/tasks/t1'), {...task, title:5})));
await t('huge title denied', assertFails(setDoc(d(me,'users/u1/tasks/t1'), {...task, title:'x'.repeat(600)})));
await t('bad notif type denied', assertFails(setDoc(d(me,'users/u1/notifications/n2'), {...notif, id:'n2', type:'spam'})));

// ------------------------------------------------------------------ teams
const ctx = (uid, email, verified = true) =>
  env.authenticatedContext(uid, { email, email_verified: verified }).firestore();
const owner = ctx('own', 'Owner@x.com');
const adeel = ctx('adl', 'adeel@x.com');
const sara = ctx('sar', 'sara@x.com');
const fake = ctx('fak', 'adeel@x.com', false); // same email, not verified
const outsider = ctx('out', 'out@x.com');
const T = 'team1';
const teamDoc = {
  id: T, name: 'SEO', color: 1, owner_id: 'own', member_ids: ['own'], manager_ids: [],
  members: { own: { name: 'Owner', email: 'owner@x.com' } }, created_at: now, updated_at: now,
};
const invite = (email, by = 'own') => ({
  id: `${T}_${email}`, team_id: T, team_name: 'SEO', email, invited_by: by,
  invited_by_name: 'Owner', created_at: now,
});
const join = (db, uid, email) => {
  const b = writeBatch(db);
  b.update(doc(db, `teams/${T}`), { member_ids: arrayUnion(uid), [`members.${uid}`]: { name: uid, email }, updated_at: now });
  b.delete(doc(db, `invites/${T}_${email}`));
  return b.commit();
};
const ttask = (id, assignee, by = 'own') => ({ ...task, id, checklist: [], assignee_id: assignee, created_by: by, assigned_by: by, assigned_at: now });

await t('team: create', assertSucceeds(setDoc(doc(owner, `teams/${T}`), teamDoc)));
await t('team: create with other members denied', assertFails(setDoc(doc(owner, 'teams/t2'), { ...teamDoc, id: 't2', member_ids: ['own', 'adl'], members: { own: teamDoc.members.own, adl: { name: 'a', email: 'a' } } })));
await t('team: create for someone else denied', assertFails(setDoc(doc(adeel, 'teams/t3'), { ...teamDoc, id: 't3' })));
await t('team: outsider cannot read', assertFails(getDoc(doc(outsider, `teams/${T}`))));
await t('invite: owner invites adeel', assertSucceeds(setDoc(doc(owner, `invites/${T}_adeel@x.com`), invite('adeel@x.com'))));
await t('invite: owner invites sara', assertSucceeds(setDoc(doc(owner, `invites/${T}_sara@x.com`), invite('sara@x.com'))));
await t('invite: outsider cannot invite', assertFails(setDoc(doc(outsider, `invites/${T}_x@x.com`), invite('x@x.com', 'out'))));
await t('invite: uppercase email denied', assertFails(setDoc(doc(owner, `invites/${T}_Big@x.com`), invite('Big@x.com'))));
await t('invite: adeel sees own invites', assertSucceeds(getDocs(query(collection(adeel, 'invites'), where('email', '==', 'adeel@x.com')))));
await t('invite: owner lists team invites', assertSucceeds(getDocs(query(collection(owner, 'invites'), where('team_id', '==', T)))));
await t('invite: outsider cannot read', assertFails(getDoc(doc(outsider, `invites/${T}_adeel@x.com`))));
await t('join: unverified email denied', assertFails(join(fake, 'fak', 'adeel@x.com')));
await t('join: no invite denied', assertFails(join(outsider, 'out', 'out@x.com')));
await t('join: adeel accepts', assertSucceeds(join(adeel, 'adl', 'adeel@x.com')));
await t('join: sara accepts', assertSucceeds(join(sara, 'sar', 'sara@x.com')));
await t('team: member can read', assertSucceeds(getDoc(doc(adeel, `teams/${T}`))));
await t('team: member cannot rename', assertFails(updateDoc(doc(adeel, `teams/${T}`), { name: 'Hacked' })));
await t('team: member cannot make self manager', assertFails(updateDoc(doc(adeel, `teams/${T}`), { manager_ids: ['adl'] })));
await t('team: member updates own name', assertSucceeds(updateDoc(doc(adeel, `teams/${T}`), { 'members.adl': { name: 'Adeel', email: 'adeel@x.com' }, updated_at: now })));
await t('team: member cannot change others name', assertFails(updateDoc(doc(adeel, `teams/${T}`), { 'members.sar': { name: 'x', email: 'x' } })));

await t('task: owner creates task for adeel', assertSucceeds(setDoc(doc(owner, `teams/${T}/tasks/a1`), ttask('a1', 'adl'))));
await t('task: owner creates task for sara', assertSucceeds(setDoc(doc(owner, `teams/${T}/tasks/s1`), ttask('s1', 'sar'))));
await t('task: assign to non-member denied', assertFails(setDoc(doc(owner, `teams/${T}/tasks/x1`), ttask('x1', 'out'))));
await t('task: member creates own task', assertSucceeds(setDoc(doc(adeel, `teams/${T}/tasks/a2`), ttask('a2', 'adl', 'adl'))));
await t('task: member cannot create for others', assertFails(setDoc(doc(adeel, `teams/${T}/tasks/a3`), ttask('a3', 'sar', 'adl'))));
await t('task: member cannot create unassigned', assertFails(setDoc(doc(adeel, `teams/${T}/tasks/a4`), ttask('a4', null, 'adl'))));
await t('task: member cannot fake creator', assertFails(setDoc(doc(adeel, `teams/${T}/tasks/a5`), ttask('a5', 'adl', 'own'))));
await t('task: member edits own task', assertSucceeds(updateDoc(doc(adeel, `teams/${T}/tasks/a2`), { title: 'Renamed', updated_at: now })));
await t('task: member cannot give own task away', assertFails(updateDoc(doc(adeel, `teams/${T}/tasks/a2`), { assignee_id: 'sar' })));
await t('task: other member cannot edit it', assertFails(updateDoc(doc(sara, `teams/${T}/tasks/a2`), { title: 'x' })));
await t('task: other member cannot delete it', assertFails(deleteDoc(doc(sara, `teams/${T}/tasks/a2`))));
await t('task: member deletes own task', assertSucceeds(deleteDoc(doc(adeel, `teams/${T}/tasks/a2`))));
await t('task: member cannot delete assigned task', assertFails(deleteDoc(doc(adeel, `teams/${T}/tasks/a1`))));
await t('task: member reads team tasks', assertSucceeds(getDocs(collection(adeel, `teams/${T}/tasks`))));
await t('task: outsider cannot read', assertFails(getDocs(collection(outsider, `teams/${T}/tasks`))));
await t('task: adeel marks own task done', assertSucceeds(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { status: 'completed', completed_at: now, updated_at: now })));
await t('task: completed_by must be yourself', assertFails(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { status: 'completed', completed_by: 'own', updated_at: now })));
await t('task: completed_by self ok', assertSucceeds(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { status: 'completed', completed_by: 'adl', updated_at: now })));
await t('task: adeel ticks checklist', assertSucceeds(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { checklist: [], updated_at: now })));
await t('task: adeel cannot edit title', assertFails(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { title: 'changed' })));
await t('task: adeel cannot reassign', assertFails(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { assignee_id: 'sar' })));
await t('task: adeel cannot cancel', assertFails(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { status: 'cancelled' })));
await t('task: adeel cannot complete saras task', assertFails(updateDoc(doc(adeel, `teams/${T}/tasks/s1`), { status: 'completed', completed_at: now, updated_at: now })));
await t('task: member cannot delete', assertFails(deleteDoc(doc(adeel, `teams/${T}/tasks/s1`))));

const comment = (id, author, taskId = 'a1', extra = {}) => ({
  id, task_id: taskId, author_id: author, author_name: author, text: 'Half done', created_at: now, ...extra,
});
await t('comment: assignee comments', assertSucceeds(setDoc(doc(adeel, `teams/${T}/comments/c1`), comment('c1', 'adl'))));
await t('comment: other member comments', assertSucceeds(setDoc(doc(sara, `teams/${T}/comments/c2`), comment('c2', 'sar'))));
await t('comment: owner comments', assertSucceeds(setDoc(doc(owner, `teams/${T}/comments/c3`), comment('c3', 'own'))));
await t('comment: cannot post as someone else', assertFails(setDoc(doc(adeel, `teams/${T}/comments/c4`), comment('c4', 'own'))));
await t('comment: empty text denied', assertFails(setDoc(doc(adeel, `teams/${T}/comments/c5`), comment('c5', 'adl', 'a1', { text: '' }))));
await t('comment: unknown task denied', assertFails(setDoc(doc(adeel, `teams/${T}/comments/c6`), comment('c6', 'adl', 'nope'))));
await t('comment: outsider cannot comment', assertFails(setDoc(doc(outsider, `teams/${T}/comments/c7`), comment('c7', 'out'))));
await t('comment: outsider cannot read', assertFails(getDocs(collection(outsider, `teams/${T}/comments`))));
await t('comment: member reads by task', assertSucceeds(getDocs(query(collection(sara, `teams/${T}/comments`), where('task_id', '==', 'a1')))));
await t('comment: cannot edit', assertFails(updateDoc(doc(adeel, `teams/${T}/comments/c1`), { text: 'edited' })));
await t('comment: cannot delete others', assertFails(deleteDoc(doc(sara, `teams/${T}/comments/c1`))));
await t('comment: author deletes own', assertSucceeds(deleteDoc(doc(sara, `teams/${T}/comments/c2`))));
await t('comment: owner deletes any', assertSucceeds(deleteDoc(doc(owner, `teams/${T}/comments/c1`))));
await t('board: adeel moves own task to review', assertSucceeds(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { stage: 'review', updated_at: now })));
await t('approval: assignee sends with note and links', assertSucceeds(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { stage: 'review', links: [{ title: 'Figma', url: 'https://figma.com/x' }], history: arrayUnion({ kind: 'submitted', by: 'adl', at: now, to: 'review', note: 'Ready' }), updated_at: now })));
await t('approval: cannot attach links to others task', assertFails(updateDoc(doc(adeel, `teams/${T}/tasks/s1`), { links: [] })));
await t('approval: too many links denied', assertFails(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { links: Array(21).fill({ title: '', url: 'https://a.com' }) })));
await t('board: bad stage denied', assertFails(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { stage: 'weird' })));
await t('board: cannot move others task', assertFails(updateDoc(doc(adeel, `teams/${T}/tasks/s1`), { stage: 'doing' })));
// links, history, work timer, @mentions
const ev = (kind, by, extra = {}) => ({ kind, by, at: now, ...extra });
await t('extras: personal task with links/history/time', assertSucceeds(setDoc(d(me,'users/u1/tasks/t1'), { ...task,
  links: [{ title: 'Brief', url: 'https://docs.google.com/x' }], history: [ev('created', 'u1')],
  time_log: [{ by: 'u1', start: now - 3600000, end: now }], timer_by: 'u1', timer_at: now })));
await t('estimate: personal task with estimate', assertSucceeds(setDoc(d(me,'users/u1/tasks/t1'), { ...task, estimate_min: 90 })));
await t('estimate: zero denied', assertFails(setDoc(d(me,'users/u1/tasks/t1'), { ...task, estimate_min: 0 })));
await t('estimate: text denied', assertFails(setDoc(d(me,'users/u1/tasks/t1'), { ...task, estimate_min: '1h' })));
await t('profile: work hours', assertSucceeds(setDoc(d(me,'users/u1'), { work_start: 540, work_end: 1050 }, { merge: true })));
await t('extras: too many links denied', assertFails(setDoc(d(me,'users/u1/tasks/t1'), { ...task, links: Array(21).fill({ title: '', url: 'https://a.com' }) })));
await t('extras: links must be a list', assertFails(setDoc(d(me,'users/u1/tasks/t1'), { ...task, links: 'https://a.com' })));
await t('timer: adeel starts timer on own task', assertSucceeds(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { timer_by: 'adl', timer_at: now, stage: 'doing', history: arrayUnion(ev('stage', 'adl', { to: 'doing' })), updated_at: now })));
await t('timer: adeel stops timer + logs time', assertSucceeds(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { timer_by: null, timer_at: null, time_log: arrayUnion({ by: 'adl', start: now - 60000, end: now }), updated_at: now })));
await t('timer: cannot start as someone else', assertFails(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { timer_by: 'own', timer_at: now })));
await t('timer: cannot time others task', assertFails(updateDoc(doc(adeel, `teams/${T}/tasks/s1`), { timer_by: 'adl', timer_at: now })));
await t('timer: owner starts timer on adeels task', assertSucceeds(updateDoc(doc(owner, `teams/${T}/tasks/a1`), { timer_by: 'own', timer_at: now, updated_at: now })));
await t('timer: adeel ticks checklist while owner timer runs', assertSucceeds(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { checklist: [], updated_at: now })));
await t('timer: adeel finishing stops the timer', assertSucceeds(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { status: 'completed', completed_by: 'adl', completed_at: now, timer_by: null, timer_at: null, time_log: arrayUnion({ by: 'own', start: now - 60000, end: now }), history: arrayUnion(ev('done', 'adl')), updated_at: now })));
await t('links: assignee can attach links to own task', assertSucceeds(updateDoc(doc(adeel, `teams/${T}/tasks/a1`), { links: [] })));
await t('links: owner adds links', assertSucceeds(updateDoc(doc(owner, `teams/${T}/tasks/a1`), { links: [{ title: '', url: 'https://drive.google.com/x' }], updated_at: now })));
await t('mention: comment with mentions', assertSucceeds(setDoc(doc(sara, `teams/${T}/comments/m1`), comment('m1', 'sar', 'a1', { text: '@adl see this', mentions: ['adl'] }))));
await t('mention: mentions must be a list', assertFails(setDoc(doc(sara, `teams/${T}/comments/m2`), comment('m2', 'sar', 'a1', { mentions: 'adl' }))));
await t('repeat: owner makes weekly task for adeel', assertSucceeds(setDoc(doc(owner, `teams/${T}/tasks/w1`), { ...ttask('w1', 'adl'), repeat: 'weekly' })));
const nextCopy = (by, extra = {}) => ({ ...ttask('w2', 'adl'), repeat: 'weekly', repeat_from: 'w1', start_at: now + 7 * 864e5, ...extra });
await t('repeat: other member cannot copy', assertFails(setDoc(doc(sara, `teams/${T}/tasks/w2`), nextCopy('sar'))));
await t('repeat: copy with changed title denied', assertFails(setDoc(doc(adeel, `teams/${T}/tasks/w2`), nextCopy('adl', { title: 'Other' }))));
await t('repeat: copy assigned to someone else denied', assertFails(setDoc(doc(adeel, `teams/${T}/tasks/w2`), nextCopy('adl', { assignee_id: 'sar' }))));
await t('repeat: copy of non-repeating task denied', assertFails(setDoc(doc(adeel, `teams/${T}/tasks/w3`), { ...nextCopy('adl'), id: 'w3', repeat_from: 'a1' })));
await t('repeat: adeel finishes + next copy (batch)', assertSucceeds((() => {
  const b = writeBatch(adeel);
  b.update(doc(adeel, `teams/${T}/tasks/w1`), { status: 'completed', completed_at: now, updated_at: now });
  b.set(doc(adeel, `teams/${T}/tasks/w2`), nextCopy('adl'));
  return b.commit();
})()));
await t('template: save own template', assertSucceeds(setDoc(doc(me, 'users/u1/templates/tp1'), { id: 'tp1', name: 'SEO audit', title: 'SEO audit', description: '', priority: 1, checklist: ['Keywords', 'Meta'], duration_min: 60, created_at: now })));
await t('template: other user denied', assertFails(getDoc(doc(other, 'users/u1/templates/tp1'))));
await t('template: bad template denied', assertFails(setDoc(doc(me, 'users/u1/templates/tp2'), { id: 'tp2', name: 5, created_at: now })));
// ------------------------------------------------------------------ inbox
const inboxItem = (id, extra = {}) => ({ id, title: 'Call Ali', notes: '', source: 'quick', created_at: now,
  due_at: null, all_day: false, priority: null, team_id: null, assignee_id: null, category_id: null, links: [],
  organized_at: null, organized_to: null, task_id: null, task_team: null, ...extra });
await t('inbox: own item', assertSucceeds(setDoc(doc(adeel, 'users/adl/inbox/i1'), inboxItem('i1'))));
await t('inbox: organized merge', assertSucceeds(setDoc(doc(adeel, 'users/adl/inbox/i1'), inboxItem('i1', { organized_at: now, organized_to: 'My Tasks', task_id: 'x', team_id: T }))));
await t('inbox: bad source denied', assertFails(setDoc(doc(adeel, 'users/adl/inbox/i2'), inboxItem('i2', { source: 'spam' }))));
await t('inbox: empty title denied', assertFails(setDoc(doc(adeel, 'users/adl/inbox/i2'), inboxItem('i2', { title: '' }))));
const fwd = (id, extra = {}) => inboxItem(id, { source: 'forwarded', from_id: 'adl', from_name: 'adl', team_id: T, ...extra });
await t('inbox: teammate forwards', assertSucceeds(setDoc(doc(adeel, 'users/sar/inbox/f1'), fwd('f1'))));
await t('inbox: forwarder cannot read it', assertFails(getDoc(doc(adeel, 'users/sar/inbox/f1'))));
await t('inbox: forwarder cannot overwrite', assertFails(setDoc(doc(adeel, 'users/sar/inbox/f1'), fwd('f1', { title: 'x' }))));
await t('inbox: forwarder cannot delete', assertFails(deleteDoc(doc(adeel, 'users/sar/inbox/f1'))));
await t('inbox: forward as someone else denied', assertFails(setDoc(doc(adeel, 'users/sar/inbox/f2'), fwd('f2', { from_id: 'own' }))));
await t('inbox: forward without shared team denied', assertFails(setDoc(doc(outsider, 'users/sar/inbox/f3'), fwd('f3', { from_id: 'out' }))));
await t('inbox: forward to non-member denied', assertFails(setDoc(doc(adeel, 'users/out/inbox/f4'), fwd('f4'))));
await t('inbox: non-forwarded source into other inbox denied', assertFails(setDoc(doc(adeel, 'users/sar/inbox/f5'), fwd('f5', { source: 'quick' }))));
await t('inbox: owner reads forwarded', assertSucceeds(getDoc(doc(sara, 'users/sar/inbox/f1'))));
await t('notif: new fields', assertSucceeds(setDoc(doc(sara, 'users/sar/notifications/n1'), { ...notif, kind: 'mention', team_id: T, actor_name: 'Adeel', snooze_until: now })));
await t('profile: notification switches', assertSucceeds(setDoc(doc(sara, 'users/sar'), { notif_assign: false, notif_approvals: true, notif_comments: false }, { merge: true })));
await t('profile: bad switch denied', assertFails(setDoc(doc(sara, 'users/sar'), { notif_assign: 'no' }, { merge: true })));

await t('role: owner makes adeel manager', assertSucceeds(updateDoc(doc(owner, `teams/${T}`), { manager_ids: ['adl'], updated_at: now })));
await t('role: manager creates task', assertSucceeds(setDoc(doc(adeel, `teams/${T}/tasks/m1`), ttask('m1', 'sar', 'adl'))));
await t('role: manager edits any task', assertSucceeds(updateDoc(doc(adeel, `teams/${T}/tasks/s1`), { title: 'Edited', updated_at: now })));
await t('role: manager cannot make others manager', assertFails(updateDoc(doc(adeel, `teams/${T}`), { manager_ids: ['adl', 'sar'] })));
await t('role: manager can invite', assertSucceeds(setDoc(doc(adeel, `invites/${T}_new@x.com`), invite('new@x.com', 'adl'))));
await t('role: manager cannot remove owner', assertFails(updateDoc(doc(adeel, `teams/${T}`), { member_ids: arrayRemove('own'), 'members.own': deleteField() })));
await t('role: manager cannot delete team', assertFails(deleteDoc(doc(adeel, `teams/${T}`))));
await t('role: manager removes sara', assertSucceeds(updateDoc(doc(adeel, `teams/${T}`), { member_ids: arrayRemove('sar'), 'members.sar': deleteField(), updated_at: now })));
await t('role: removed sara cannot read tasks', assertFails(getDocs(collection(sara, `teams/${T}/tasks`))));
await t('leave: owner cannot leave', assertFails(updateDoc(doc(owner, `teams/${T}`), { member_ids: arrayRemove('own'), 'members.own': deleteField() })));
await t('leave: adeel (manager) leaves', assertSucceeds(updateDoc(doc(adeel, `teams/${T}`), { member_ids: arrayRemove('adl'), manager_ids: arrayRemove('adl'), 'members.adl': deleteField(), updated_at: now })));
await t('leave: adeel no longer reads team', assertFails(getDoc(doc(adeel, `teams/${T}`))));
await t('invite: invitee can decline (delete)', assertSucceeds(deleteDoc(doc(ctx('nw', 'new@x.com'), `invites/${T}_new@x.com`))));
await t('workload: owner sets hours per week', assertSucceeds(updateDoc(doc(owner, `teams/${T}`), { week_hours: 35, updated_at: now })));
await t('workload: bad hours denied', assertFails(updateDoc(doc(owner, `teams/${T}`), { week_hours: 500 })));
await t('workload: member cannot set hours', assertFails(updateDoc(doc(sara, `teams/${T}`), { week_hours: 10 })));
await t('team: owner renames', assertSucceeds(updateDoc(doc(owner, `teams/${T}`), { name: 'SEO Team', updated_at: now })));
await t('team: owner deletes task', assertSucceeds(deleteDoc(doc(owner, `teams/${T}/tasks/a1`))));
await t('team: owner deletes team', assertSucceeds(deleteDoc(doc(owner, `teams/${T}`))));

await env.cleanup();
console.log(`ok=${ok} bad=${bad}`); process.exit(bad?1:0);
