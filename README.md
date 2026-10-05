# Redmine LDAP Sync

[![Redmine](https://img.shields.io/badge/Redmine-6.x-red)](https://www.redmine.org)
[![Rails](https://img.shields.io/badge/Rails-7.2-red)](https://rubyonrails.org)
[![Ruby](https://img.shields.io/badge/Ruby-3.x-red)](https://www.ruby-lang.org)
[![License](https://img.shields.io/badge/License-GPL%20v3-blue)](LICENSE)

A Redmine plugin that synchronizes users and groups automatically from LDAP/Active Directory.

> **This is a Rails 7 / Redmine 6 compatible port** of the original
> [redmine_ldap_sync](https://github.com/thorin/redmine_ldap_sync) plugin
> by [Ricardo Santos](https://github.com/thorin).
>
> The original plugin supported Redmine 3.x / Rails 4.
> This version has been fully ported and enhanced for modern Redmine installations.
> 
## Tested with:

| Component | Version |
|-----------|---------|
| Redmine   | 6.1.2 |
| Rails     | 7.2.3 |
| Ruby      | 3.4.9 |
| PostgreSQL| 16 |

---

## What's New in v3.0.0

| Feature | Description |
|---------|-------------|
| 🔄 **Rails 7.2 compatible** | Zeitwerk autoloader, Turbo, updated JavaScript |
| 🏗️ **Redmine 6.x compatible** | Tabler Icons UI, modern asset pipeline |
| 💎 **Ruby 3.x compatible** | Removed SortedSet, fixed keyword arguments |
| ⏰ **Built-in scheduler** | No host cron job needed — configure sync interval in the UI |
| ▶️ **Manual sync button** | Run an immediate sync from the admin UI |
| 🧪 **Improved Test tab** | Friendly output with LDAP connection status |
| 🔍 **Flexible user search** | Search by `john.doe` or `john.doe@company.com` |

---

## Requirements

| Component | Version |
|-----------|---------|
| Redmine   | 6.0 or higher |
| Rails     | 7.2     |
| Ruby      | 3.2 or higher |

---

## Installation

### 1. Copy the plugin

```bash
cd /path/to/redmine/plugins
git clone https://github.com/jzsgbr/redmine_ldap_sync.git
```

### 2. Run migrations

```bash
cd /path/to/redmine
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

### 3. Restart Redmine

```bash
# Docker:
docker compose down && docker compose up -d

# Passenger/Puma:
touch tmp/restart.txt
```

---

## Docker Setup

Add the timezone to your `docker-compose.yml`:

```yaml
services:
  redmine:
    environment:
      TZ: Europe/Budapest  # set your timezone
```

---

## Configuration

### Step 1 — LDAP Authentication

Configure your LDAP server under **Administration → LDAP Authentication**.

**Active Directory typical settings:**

| Field | Value |
|-------|-------|
| Host | `your-dc.domain.local` |
| Port | `636` (LDAPS) or `389` (LDAP) |
| Base DN | `DC=domain,DC=local` |
| Login attribute | `mail` or `userPrincipalName` |
| Firstname attribute | `sn` |
| Lastname attribute | `givenName` |

### Step 2 — LDAP Sync Settings

Go to **Administration → LDAP Synchronization** and click your LDAP server.

#### LDAP Settings tab

| Field | Description | AD Default |
|-------|-------------|------------|
| Groups base DN | Where to search for groups | `OU=Groups,DC=domain,DC=local` |
| Users objectclass | LDAP object class for users | `user` |
| Groups objectclass | LDAP object class for groups | `group` |
| Group name pattern | Regex filter for groups to sync | `^redmine_.*$` |
| Group membership | How group membership is stored | `On the user class` |
| Group name (group) | Attribute for group name | `samaccountname` |
| Groups (user) | Attribute linking user to groups | `memberof` |
| Groupid (group) | Unique group identifier | `distinguishedname` |

#### Synchronization Actions tab

| Field | Description |
|-------|-------------|
| Synchronize on login | Sync user data on every login |
| Users must be members of | Required group for Redmine access |
| Create users | Auto-create users found in LDAP |
| Create groups | Auto-create groups found in LDAP |
| Remove users | Remove users that are no longer present in LDAP |
| Remove groups | Remove groups that are no longer present in LDAP |
---

## Scheduler

The plugin includes a **built-in scheduler** — no host cron job required.

Go to **Administration → LDAP Synchronization → Schedule tab**:

| Frequency | Description |
|-----------|-------------|
| Every 15 minutes | Runs every 15 min |
| Every 30 minutes | Runs every 30 min |
| Every hour | Runs hourly at the configured minute (0–59) |
| Once a day | Runs daily at the configured hour:minute |

> **Note:** The scheduler triggers on incoming HTTP requests.
> It uses a database timestamp to prevent duplicate runs with multiple Puma workers.

---

## Manual Sync

**From the UI:** Administration → LDAP Synchronization → Schedule tab → **Run now**

**From the command line:**

```bash
# Sync both groups and users
bundle exec rake redmine:plugins:ldap_sync:sync_all RAILS_ENV=production

# Sync groups only
bundle exec rake redmine:plugins:ldap_sync:sync_groups RAILS_ENV=production

# Sync users only
bundle exec rake redmine:plugins:ldap_sync:sync_users RAILS_ENV=production
```

---

## Testing the Connection

Use the **Test tab** to verify your LDAP configuration:

1. Enter a **user login or UPN** (e.g. `john.doe` or `john.doe@company.com`)
2. Enter a **group name** (e.g. `redmine_users`)
3. Click **Execute**

A successful result:
```
User "john.doe@company.com":
    First name = John
    Last name = Doe
    Email = john.doe@company.com
    Groups = ["redmine_users", "redmine_admins"]

Group "redmine_users":
    No fields

✓ LDAP connection OK — sync is operational.
```

---

## Troubleshooting

**Users not being created**
- Ensure the `mail` attribute is filled in AD
- Ensure `sn` (surname) and `givenName` are not empty in AD
- Verify the user is a member of the required group

**Scheduler not running**
- Check the plugin is **Enabled** on the LDAP Servers list
- Verify **Enable automatic synchronization** is checked in the Schedule tab
- The scheduler triggers on page loads — Redmine must be receiving HTTP requests

**Plugin not loading**
- Run migrations: `bundle exec rake redmine:plugins:migrate RAILS_ENV=production`
- Fully restart Redmine: `docker compose down && docker compose up -d`

---

## Changelog

### v3.0.1 (2026-10-05)

- Fixed: automatic scheduler failed with `undefined method running_rake!` because the `to_prepare` block in `init.rb` did not run on Redmine 6 - plugin libraries are now loaded in `after_initialize`
- Scheduler now loads the infectors itself before running (same safeguard as the manual sync)

### v3.0.0 (2026)
- Full Rails 7.2 / Redmine 6.x / Ruby 3.x compatibility
- Zeitwerk autoloader compatibility (`vendor/` directory structure)
- Built-in scheduler with UI (replaces host cron jobs)
- Manual sync button in the admin UI
- Improved Test tab with readable, user-friendly output
- FQDN-optional LDAP user search (`john.doe` or `john.doe@company.com`)
- Modern Redmine 6 UI (Tabler Icons, no PNG icon glitches)
- Removed deprecated Rails APIs: `unloadable`, `alias_method_chain`, `SortedSet`
- Fixed `Net::LDAP::Entry` compatibility with net-ldap 0.17+
- Separate schedule form (avoids nested form issues in Rails 7)

### v2.1.1 (original by Ricardo Santos)
- Last version supporting Redmine 3.x / Rails 4

---

## Credits

- **Original author:** [Ricardo Santos](https://github.com/thorin) —
  [redmine_ldap_sync](https://github.com/thorin/redmine_ldap_sync)
- **Rails 7 port & enhancements:** [Gabor Jozsa](https://github.com/jzsgbr)

## License

[GNU General Public License v3.0](LICENSE)
