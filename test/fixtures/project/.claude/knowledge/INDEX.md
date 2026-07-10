# Knowledge Map
# Maps source files to the knowledge entries that are relevant to them.
# Grep the left side for file paths, grep the right side for concepts/categories.
#
# Format: relative/path/to/source_file -> [category/entry-name.md, ...]

app/models/order.rb -> [architecture/order-lifecycle.md, gotchas/order-cache.md]
app/channels/order_channel.rb -> [architecture/actioncable-channels.md]
app/services/checkout_service.rb -> [architecture/order-lifecycle.md]
