import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import fs from 'fs';

const root = 'c:/Users/haza/Documents/Pull Studio The Basic Club Kit v1.3';
const args = JSON.parse(fs.readFileSync(`${root}/.tmp/mcp-set-source.json`, 'utf8'));

const transport = new StdioClientTransport({
  command: 'cmd',
  args: ['/c', 'npx', '-y', '@chrrxs/robloxstudio-mcp@latest'],
});

const client = new Client({ name: 'clubkit-invoke', version: '1.0.0' });
await client.connect(transport);
const result = await client.callTool({ name: 'set_script_source', arguments: args });
console.log(JSON.stringify(result));
await client.close();
