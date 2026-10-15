// Checks firestore.rules against the exact shapes of the app's writes.
// Run: cd tool/rules_test && npm install && npm test   (needs Java)
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, deleteDoc, getDoc } from 'firebase/firestore';
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
await env.cleanup();
console.log(`ok=${ok} bad=${bad}`); process.exit(bad?1:0);
