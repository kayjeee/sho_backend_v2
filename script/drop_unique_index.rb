require_relative '../config/environment'

begin
  puts "Attempting to drop unique_participants_per_school index..."
  Conversation.collection.indexes.drop_one('unique_participants_per_school')
  puts "Index dropped successfully."
rescue => e
  puts "Failed to drop index (it might not exist): #{e.message}"
end
