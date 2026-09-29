// Exercise the actual embedded scripts without making requests to Notion.
// Run with: node Scripts/test-notion.mjs
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import test from 'node:test';
const source = readFileSync(new URL('../Sources/Providers/NotionSite.swift', import.meta.url), 'utf8');
const shared = source.match(/notionSpacesScript = """\n([\s\S]*?)\n    """/)[1];
const script = source.match(/script: """\n([\s\S]*?)\n            """/)[1];
const probe = source.match(/authProbeScript: """\n([\s\S]*?)\n            """/)[1];
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const record = value => ({value: {value}});
const spaces = {user: {notion_user: {user: record({id:'user'})}, space: {
    'aaa-free': record({id:'aaa-free', name:'Personal', subscription_tier:'free'}),
    'bbb-paid': record({id:'bbb-paid', name:'Team', subscription_tier:'business'}),
}}};
async function run({preferred='', root=spaces, status=200, usageStatus=200, auth=false}={}) {
    const calls=[];
    const fetch = async (url, options) => {
        calls.push({url, options});
        const code = calls.length === 1 ? status : usageStatus;
        return {status:code, ok: code===200, json: async () => calls.length===1 ? root : {window:{used:10,limit:100}}};
    };
    const body=(auth?probe:script).replace('\\(encoded)', JSON.stringify(preferred)).replace('\\(notionSpacesScript)',shared);
    return {result:JSON.parse(await new AsyncFunction('fetch',body)(fetch)),calls};
}
test('selects Business ahead of a free workspace, with credentials on both POSTs', async()=>{
    const {result,calls}=await run();
    assert.equal(JSON.parse(calls[1].options.body).spaceId,'bbb-paid');
    assert.equal(JSON.parse(result.body).workspaceName,'Team');
    for(const {options,url} of calls) {
        assert.equal(options.method,'POST'); assert.equal(options.credentials,'include');
        assert.ok(url.startsWith('/api/v3/'));
    }
});
test('explicit workspace accepts undashed IDs', async()=>{
    const {calls}=await run({preferred:'AAAFREE'});
    assert.equal(JSON.parse(calls[1].options.body).spaceId,'aaa-free');
});
test('unavailable explicit workspace never falls back or fetches another allowance', async()=>{
    const {result,calls}=await run({preferred:'missing'});
    assert.equal(JSON.parse(result.body).error,'workspace_missing'); assert.equal(calls.length,1);
});
test('workspace input remains data even with script punctuation', async()=>{
    const {result}=await run({preferred:'"; throw new Error("injected"); //'});
    assert.equal(JSON.parse(result.body).error,'workspace_missing');
});
test('expired session and throttling preserve HTTP status', async()=>{
    for(const status of [401,403,429,500]) {
        const {result,calls}=await run({status});
        assert.equal(result.status,status); assert.equal(calls.length,1);
        assert.equal((await run({usageStatus:status})).result.status,status);
    }
});
test('multiple signed-in accounts are not silently mixed', async()=>{
    const root={...spaces,other:{notion_user:{other:record({id:'other'})}}};
    const {result,calls}=await run({root});
    assert.equal(JSON.parse(result.body).error,'ambiguous_account'); assert.equal(calls.length,1);
});
test('probe accepts a real identity and rejects empty or expired sessions', async()=>{
    assert.deepEqual((await run({auth:true})).result,{authenticated:true,fingerprint:'user'});
    assert.equal((await run({auth:true,root:{}})).result.authenticated,false);
    assert.equal((await run({auth:true,status:401})).result.authenticated,false);
});
test('single-wrapped workspace records work too', async()=>{
    const root={user:{notion_user:{user:{value:{id:'user'}}},space:{one:{value:{id:'one',subscription_tier:'enterprise'}}}}};
    const {calls}=await run({root}); assert.equal(JSON.parse(calls[1].options.body).spaceId,'one');
});
