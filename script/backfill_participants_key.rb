require_relative '../config/environment'

puts "Backfilling participants_key for Conversations..."
count = 0
Conversation.all.each do |c|
  c.send(:normalise_participant_ids)
  c.save!(validate: false)
  count += 1
end
puts "Done backfilling #{count} conversations."
