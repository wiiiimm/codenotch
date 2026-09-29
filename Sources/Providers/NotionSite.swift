import Foundation

extension Sites {
    /// The session stays inside WebKit. Only allowance numbers and the selected
    /// workspace name cross into Swift; no cookie or account records do.
    static func notion(workspaceID: String = "") -> WebSessionProvider.Site {
        let encoded = String(data: try! JSONEncoder().encode(workspaceID), encoding: .utf8)!
        return WebSessionProvider.Site(
            id: "notion", displayName: "Notion AI", glyph: .notion,
            origin: URL(string: "https://app.notion.com/")!,
            script: """
            const preferred = \(encoded);
            \(notionSpacesScript)
            const result = await readSpaces();
            if (result.status !== 200) return JSON.stringify(result);
            if (result.error) return JSON.stringify({status: 200, body: JSON.stringify({error: result.error})});
            const normalise = id => String(id).replace(/-/g, '').toLowerCase().trim();
            const spaces = result.spaces;
            const workspace = preferred.trim()
                ? spaces.find(s => normalise(s.id) === normalise(preferred))
                : spaces.find(s => ['business', 'enterprise'].includes(String(s.subscription_tier).toLowerCase())) || spaces[0];
            if (!workspace) return JSON.stringify({status: 200, body: JSON.stringify({
                error: preferred.trim() ? 'workspace_missing' : 'no_workspaces'
            })});
            const response = await fetch('/api/v3/getCreditRateLimitStatus', {
                method: 'POST', credentials: 'include',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({spaceId: workspace.id})
            });
            if (!response.ok) return JSON.stringify({status: response.status, body: ''});
            return JSON.stringify({status: 200, body: JSON.stringify({
                workspaceName: workspace.name, usage: await response.json()
            })});
            """,
            authProbeScript: """
            \(notionSpacesScript)
            const result = await readSpaces();
            return JSON.stringify({authenticated: result.status === 200 && !!result.userID,
                                   fingerprint: result.userID || null});
            """,
            associatedHosts: ["notion.com", "notion.so"],
            managePath: "", headlineID: "rolling", weeklyID: "month",
            parse: { try NotionUsage.windows(fromJSON: $0) }
        )
    }

    private static let notionSpacesScript = """
    const readSpaces = async () => {
        const response = await fetch('/api/v3/getSpaces', {
            method: 'POST', credentials: 'include',
            headers: {'Content-Type': 'application/json'}, body: '{}'
        });
        if (!response.ok) return {status: response.status, body: ''};
        const root = await response.json();
        const object = value => value && typeof value === 'object' && !Array.isArray(value);
        const unwrap = record => {
            if (!object(record)) return null;
            if (object(record.value)) record = record.value;
            if (object(record.value)) record = record.value;
            return record;
        };
        if (!object(root)) throw new Error('Invalid Notion workspace response');
        const users = Object.keys(root).filter(id => {
            const user = unwrap(root[id]?.notion_user?.[id]);
            return user && user.id === id;
        });
        if (!users.length && !Object.keys(root).length) return {status: 401, body: ''};
        if (users.length !== 1) return {status: 200, error: 'ambiguous_account'};
        const userID = users[0];
        const records = root[userID].space || {};
        const spaces = Object.keys(records).sort().flatMap(id => {
            const record = unwrap(records[id]);
            return record ? [{...record, id: record.id || id}] : [];
        });
        return {status: 200, userID, spaces};
    };
    """
}
