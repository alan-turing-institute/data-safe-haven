"""Shared Caddy container configuration for SRE user services.

Keep these in one place so an image or resource adjustment cannot silently
leave the Gitea, HedgeDoc, remote desktop, and Nexus proxies out of sync.
"""

CADDY_IMAGE = "caddy:2.11.4"
CADDY_NAME = "caddy"
CADDY_CPU = 0.5
CADDY_MEMORY_GB = 0.5
CADDY_CONFIG_MOUNT_PATH = "/etc/caddy"
CADDY_CONFIG_VOLUME_NAME = "caddy-etc-caddy"
