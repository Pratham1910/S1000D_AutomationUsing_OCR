# Scheduled maintenance backend entrypoint.
# Reuses the shared S1000D converter implementation, which now includes
# dedicated `sched` DM generation and schema mapping logic.

require_relative 's1000d1'
