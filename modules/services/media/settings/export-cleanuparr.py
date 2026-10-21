import argparse
import json
import pathlib
import sqlite3


columns = {
    "arr_configs": "id type failed_import_max_strikes",
    "download_clients": "id enabled name type_name type host username password url_base external_url download_directory_source download_directory_target",
    "arr_instances": "id enabled arr_config_id name url api_key version external_url",
    "blacklist_sync_configs": "id enabled cron_expression blacklist_path",
    "slow_rules": "id reset_strikes_on_progress max_time_hours min_speed ignore_above_size queue_cleaner_config_id name enabled max_strikes privacy_type min_completion_percentage max_completion_percentage delete_private_torrents_from_client change_category ignore_while_alt_speed_active",
    "stall_rules": "id reset_strikes_on_progress minimum_progress queue_cleaner_config_id name enabled max_strikes privacy_type min_completion_percentage max_completion_percentage delete_private_torrents_from_client change_category",
    "queue_cleaner_configs": "id cron_expression downloading_metadata_max_strikes enabled failed_import_delete_private failed_import_ignore_private failed_import_max_strikes failed_import_pattern_mode failed_import_patterns failed_import_skip_if_not_found_in_client ignored_downloads use_advanced_scheduling process_no_content_id failed_import_change_category failed_import_force_import failed_import_force_import_max_tries",
    "seeker_instance_configs": "id arr_instance_id enabled skip_tags active_download_limit min_cycle_time_days monitored_only use_cutoff use_custom_format_score ignore_struck_downloads",
    "download_cleaner_configs": "id cron_expression enabled ignored_downloads use_advanced_scheduling",
    "seeker_configs": "id post_release_grace_hours proactive_search_enabled search_enabled search_interval selection_strategy use_round_robin",
    "content_blocker_configs": "id cron_expression delete_if_any_file_blocked delete_private enabled ignore_private ignored_downloads lidarr_blocklist_path lidarr_blocklist_type lidarr_enabled process_no_content_id radarr_blocklist_path radarr_blocklist_type radarr_enabled readarr_blocklist_path readarr_blocklist_type readarr_enabled sonarr_blocklist_path sonarr_blocklist_type sonarr_enabled use_advanced_scheduling whisparr_blocklist_path whisparr_blocklist_type whisparr_enabled sportarr_blocklist_path sportarr_blocklist_type sportarr_enabled lazy_librarian_blocklist_path lazy_librarian_blocklist_type lazy_librarian_enabled",
    "general_configs": "id auth_disable_auth_for_local_addresses auth_trust_forwarded_headers auth_trusted_networks connectivity_check_enabled connectivity_check_urls display_support_banner dry_run history_retention_days http_certificate_validation http_max_retries http_send_user_agent http_timeout ignored_downloads log_archive_enabled log_archive_retained_count log_archive_time_limit_hours log_level log_retained_file_count log_rolling_size_mb log_time_limit_hours status_check_enabled strike_inactivity_window_hours",
}
empty_tables = {
    "notification_configs", "notifiarr_configs", "apprise_configs", "ntfy_configs",
    "pushover_configs", "telegram_configs", "discord_configs", "gotify_configs",
    "deluge_seeding_rules", "q_bit_seeding_rules", "r_torrent_seeding_rules",
    "transmission_seeding_rules", "u_torrent_seeding_rules", "orphaned_files_configs",
    "unlinked_configs", "dead_torrent_configs",
}
runtime = {"seeker_instance_configs": {"last_processed_at", "current_cycle_id", "total_eligible_items"}}
secret_columns = {
    "download_clients": {"host", "username", "password", "url_base", "external_url"},
    "arr_instances": {"url", "api_key", "external_url"},
}


def export(directory):
    connection = sqlite3.connect("file:" + str(directory / "cleanuparr.db") + "?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    connection.execute("BEGIN")
    actual_tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    expected = set(columns) | empty_tables | {"__EFMigrationsLock", "__EFMigrationsHistory", "blacklist_sync_history"}
    if actual_tables != expected:
        raise ValueError("Unexpected configuration tables; review schema before export")
    result = {
        "schema": [row[0] for row in connection.execute(
            "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL "
            "AND name NOT LIKE 'sqlite_%' ORDER BY type DESC,name"
        )],
        "migrations": {"__EFMigrationsHistory": [dict(row) for row in connection.execute(
            "SELECT * FROM __EFMigrationsHistory ORDER BY migration_id"
        )]},
        "tables": {},
    }
    secrets = {}
    for table in sorted(set(columns) | empty_tables):
        info = list(connection.execute(f'PRAGMA table_info("{table}")'))
        keys = [row[1] for row in sorted(info, key=lambda row: row[5]) if row[5]]
        if table in empty_tables:
            if connection.execute(f'SELECT count(*) FROM "{table}"').fetchone()[0]:
                raise ValueError("Previously empty settings table populated; review before export")
            selected = [row[1] for row in info]
            rows = []
        else:
            selected = columns[table].split()
            if set(selected) | runtime.get(table, set()) != {row[1] for row in info}:
                raise ValueError("Unexpected configuration columns; review schema before export")
            names = ','.join(f'"{column}"' for column in selected)
            order = ','.join(f'"{column}"' for column in keys)
            rows = [dict(row) for row in connection.execute(f'SELECT {names} FROM "{table}" ORDER BY {order}')]
            for row in rows:
                for column in secret_columns.get(table, set()):
                    if row[column] is not None:
                        name = "cleanuparr-" + table.replace("_", "-") + "-" + str(row[keys[0]]) + "-" + column.replace("_", "-")
                        secrets[name] = row[column]
                        row[column] = {"__sops": name}
        result["tables"][table] = {"key": keys, "columns": selected, "rows": rows}
        if table == "seeker_instance_configs":
            result["tables"][table]["insert_defaults"] = {
                "current_cycle_id": "00000000-0000-0000-0000-000000000000", "total_eligible_items": 0,
            }
    return result, secrets


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["public", "secrets"])
    args = parser.parse_args()
    snapshot, secrets = export(pathlib.Path("/var/lib/cleanuparr"))
    print(json.dumps(snapshot if args.mode == "public" else {"settings": json.dumps(secrets)}, indent=2))
