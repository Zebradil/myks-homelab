load("@ytt:yaml", "yaml")
load("@ytt:json", "json")
load("secrets.star", "sops")
load("notifications.lib.yaml", "templates")

def gen_template(message, notify=True):
  payload = {
    "chat_id": sops("1", "telegram.chatId"),
    "message_thread_id": sops("1", "telegram.topicId"),
    "text": message,
    "parse_mode": "HTML"
  }
  if not notify:
    payload["disable_notification"] = True
  end
  return yaml.encode({
    "webhook": {
      "telegram-html": {
        "method": "POST",
        "body": json.encode(payload)
      }
    }
  })
end

def gen_templates():
  return {"template." + t["name"]: gen_template(t["message"], t["notify"]) for t in templates()}
end

# vim: set ts=2 sw=2 et:
