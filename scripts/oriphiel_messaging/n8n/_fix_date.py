import json
from pathlib import Path

p = Path(__file__).with_name("oriphiel-live-process.json")
data = json.loads(p.read_text(encoding="utf-8"))

new_js = r"""const acc = $('Get Account').first().json;
const mail = $('When Called by Stub').first();
const j = mail.json;

if (!acc?.account_id) {
  throw new Error('Nema account_id za ACCOUNT_EMAIL=' + (j.ACCOUNT_EMAIL || '?'));
}

function header(name) {
  const h = j.headers || j.metadata || {};
  const key = Object.keys(h).find(k => k.toLowerCase() === name.toLowerCase());
  return key ? h[key] : null;
}
function pickAngle(s) {
  if (!s) return null;
  const m = String(s).match(/<([^>]+)>/);
  return m ? m[1].toLowerCase() : String(s).trim().toLowerCase();
}
function parseFrom(j) {
  if (j.from?.value?.[0]?.address) return String(j.from.value[0].address).trim().toLowerCase();
  if (typeof j.from === 'string') return j.from.trim().toLowerCase();
  return 'unknown@unknown';
}
function threadKey(j) {
  const inReply = pickAngle(header('in-reply-to') || j.inReplyTo);
  if (inReply) return inReply;
  const refs = String(header('references') || j.references || '');
  const rm = refs.match(/<([^>]+)>/);
  if (rm) return rm[1].toLowerCase();
  const mid = pickAngle(header('message-id') || j.messageId);
  if (mid) return mid;
  const uid = j.attributes?.uid ?? j.uid ?? 'unknown';
  return 'uid-' + uid;
}
/** IMAP Date header → ISO za Postgres timestamptz (ne RFC "Sun, 23 Aug ... (UTC)") */
function toIsoDate(raw) {
  if (raw == null || raw === '') return null;
  if (raw instanceof Date && !Number.isNaN(raw.getTime())) return raw.toISOString();
  let s = String(raw).trim();
  // ukloni trailing " (UTC)" / " (CEST)" koje Postgres ne voli
  s = s.replace(/\s*\([^)]*\)\s*$/, '').trim();
  const d = new Date(s);
  if (!Number.isNaN(d.getTime())) return d.toISOString();
  return null;
}

const uid = j.attributes?.uid ?? j.uid;
const binary = mail.binary ?? {};

return [{
  json: {
    account_id: acc.account_id,
    account_email: j.ACCOUNT_EMAIL,
    from_address: parseFrom(j),
    subject: j.subject ?? '',
    textPlain: j.textPlain ?? j.text ?? '',
    textHtml: j.textHtml ?? '',
    uid,
    date: toIsoDate(j.date ?? header('date')),
    external_id: 'uid-' + uid,
    thread_key: threadKey(j),
    mode: 'live',
    has_attachments: Object.keys(binary).length > 0
  },
  binary,
  pairedItem: { item: 0 }
}];"""

for node in data["nodes"]:
    if node.get("name") == "Normalize Mail (Live)":
        node["parameters"]["jsCode"] = new_js
        break
else:
    raise SystemExit("Normalize Mail (Live) not found")

p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok")
