#!/usr/bin/env python3
"""
Automatically switch Karabiner Elements profiles based on the active application.
"""
import json
import logging
import re
import subprocess
import time
from pathlib import Path
from typing import Optional

KARABINER_CLI = "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
CONFIG_PATH = Path.home() / ".config" / "karabiner-profile-switcher" / "config.json"

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


def load_config() -> dict:
    """Load configuration from file."""
    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH, 'r') as f:
                loaded_config = json.load(f)
                logger.info(f"Loaded configuration from {CONFIG_PATH}")
                return loaded_config
        except Exception as e:
            logger.error(f"Error loading config from {CONFIG_PATH}: {e}")
            logger.info("Using empty configuration")
            return {"rules": []}
    else:
        logger.info(f"No config found at {CONFIG_PATH}, using empty configuration")
        return {"rules": []}


def match_rule(rule: dict, app_name: str, window_title: Optional[str]) -> bool:
    """Check if a rule matches the current app and window."""
    app_pattern = rule.get("app_name_pattern")
    window_pattern = rule.get("window_title_pattern")

    # If no pattern is specified, it matches everything (catch-all)
    # If patterns are specified, they must match
    if app_pattern:
        app_matches = bool(re.search(app_pattern, app_name or ""))
    else:
        app_matches = True  # No pattern means it matches

    if window_pattern:
        window_matches = bool(re.search(window_pattern, window_title or ""))
    else:
        window_matches = True  # No pattern means it matches

    # Both conditions must be satisfied
    return app_matches and window_matches


def get_profile_for_app(config: dict, app_name: str, window_title: Optional[str]) -> Optional[str]:
    """Determine which profile should be active based on rules.

    Rules are evaluated top-to-bottom. The first matching rule's profile is returned.
    Returns None if no rule matches.
    """
    for rule in config["rules"]:
        if match_rule(rule, app_name, window_title):
            return rule["profile"]

    return None


def get_frontmost_app() -> Optional[str]:
    """Get the name of the frontmost application."""
    script = 'tell application "System Events" to get name of first process whose frontmost is true'
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None


def get_frontmost_window_title() -> Optional[str]:
    """Get the title of the frontmost window."""
    script = '''
    tell application "System Events"
        set frontApp to first process whose frontmost is true
        try
            set windowTitle to name of front window of frontApp
            return windowTitle
        on error
            return ""
        end try
    end tell
    '''
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            check=True,
        )
        title = result.stdout.strip()
        return title if title else None
    except subprocess.CalledProcessError as e:
        logger.error(f"Error getting window title: {e.stderr}")
        return None


def switch_profile(profile_name: str) -> bool:
    """Switch to the specified Karabiner profile.

    Returns True if the switch was successful, False otherwise.
    """
    try:
        subprocess.run(
            [KARABINER_CLI, "--select-profile", profile_name],
            check=True,
        )
        logger.info(f"Switched to profile: {profile_name}")
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Error switching profile: {e}")
        return False


def main() -> None:
    """Main loop to monitor active application and switch profiles."""
    # Load configuration
    config: dict = load_config()

    # Get polling interval from config, default to 1 second
    polling_interval: float = config.get("polling_interval_seconds", 1.0)

    logger.info("Karabiner profile switcher started")
    logger.info(f"Polling interval: {polling_interval} seconds")

    current_profile: Optional[str] = None
    previous_app: Optional[str] = None

    while True:
        try:
            app = get_frontmost_app()
            window_title = get_frontmost_window_title()

            if app:
                if app != previous_app:
                    logger.info(f"Frontmost app changed to: {app} (window: {window_title})")
                    previous_app = app

                # Determine which profile should be active
                desired_profile = get_profile_for_app(config, app, window_title)
                if desired_profile is not None and desired_profile != current_profile:
                    if switch_profile(desired_profile):
                        current_profile = desired_profile

            time.sleep(polling_interval)
        except KeyboardInterrupt:
            logger.info("Exiting...")
            break
        except Exception as e:
            logger.error(f"Error: {e}")
            time.sleep(1)


if __name__ == "__main__":
    main()
