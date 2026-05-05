# script/cleanup_conversations.rb
# This script deletes duplicate conversations where the participant_ids are identical (once sorted).

puts "Starting Conversation cleanup..."

all_conversations = Conversation.all
conversations_to_keep = {} # Key: sorted participant_ids string, Value: first found conversation_id
duplicates_count = 0

all_conversations.each do |conv|
  sorted_participants = (conv.participant_ids || []).map(&:to_s).sort
  key = sorted_participants.join(',')

  if conversations_to_keep.has_key?(key)
    puts "Found duplicate conversation: #{conv.id} for participants: #{key}. Deleting..."

    # Optional: Reassign messages to the kept conversation before deleting
    # kept_conv_id = conversations_to_keep[key]
    # conv.messages.update_all(conversation_id: kept_conv_id)

    conv.destroy
    duplicates_count += 1
  else
    conversations_to_keep[key] = conv.id
  end
end

puts "Cleanup complete. Deleted #{duplicates_count} duplicate conversations."
