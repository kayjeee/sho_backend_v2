require_relative '../config/environment'

# Mocking @current_user for title helper testing
class MockController < Api::V1::ConversationsController
  attr_accessor :current_user
  def initialize(user)
    @current_user = user
  end
end

puts "--- Starting Group Conversation Backend Tests ---"

# Setup
u1 = User.create!(email: "alice@example.com", auth0_id: "alice", name: "Alice Smith")
u2 = User.create!(email: "bob@example.com", auth0_id: "bob", name: "Bob Jones")
u3 = User.create!(email: "charlie@example.com", auth0_id: "charlie", name: "Charlie Brown")
u4 = User.create!(email: "david@example.com", auth0_id: "david", name: "David Miller")
u5 = User.create!(email: "eve@example.com", auth0_id: "eve", name: "Eve Adams")
school = School.create!(name: "Testing Academy")

begin
  ctrl = MockController.new(u1)

  # 1. Test 1-on-1 logic with participants_key
  puts "\n1. Testing 1-on-1 logic..."
  all_p1 = [u1.id.to_s, u2.id.to_s].sort
  c1 = Conversation.create!(participant_ids: all_p1, school_id: school.id, user_id: u1.id)
  puts "Created C1: #{c1.id}, participants_key: #{c1.participants_key}"

  # Search for it again (simulating refined controller logic)
  p_key = all_p1.join(',')
  c1_found = Conversation.where(participants_key: p_key, group_name: nil).first
  puts "Found C1 again via participants_key: #{c1_found&.id == c1.id}"

  # 2. Test Group fresh creation (3 participants)
  puts "\n2. Testing Group fresh creation..."
  all_p2 = [u1.id.to_s, u2.id.to_s, u3.id.to_s].sort
  c2 = Conversation.create!(participant_ids: all_p2, school_id: school.id, user_id: u1.id)
  puts "Created C2 (3 participants): #{c2.id}, participants_key: #{c2.participants_key}"
  puts "Is C2 a group? #{c2.group?}"

  # 3. Test Named Group (Same participants as C1)
  puts "\n3. Testing Named Group..."
  group_name = "Project X"
  c3 = Conversation.create!(participant_ids: all_p1, group_name: group_name, school_id: school.id, user_id: u1.id)
  puts "Created C3 (Named Group): #{c3.id}, name: #{c3.group_name}, key: #{c3.participants_key}"
  puts "Is C3 a group? #{c3.group?}"

  # 4. Test Uniqueness (Named vs Unnamed)
  puts "\n4. Testing Uniqueness..."
  begin
    Conversation.create!(participant_ids: all_p1, school_id: school.id, user_id: u1.id)
    puts "FAILED: Should have raised uniqueness error for duplicate unnamed 1-on-1"
  rescue => e
    puts "SUCCESS: Caught expected error: #{e.class}"
  end

  # 5. Test Title Helper Logic
  puts "\n5. Testing Title Helper Logic..."
  p_hashes = [u1, u2, u3, u4, u5].map { |u| { id: u.id.to_s, name: u.name } }

  puts "Title (1 other): #{ctrl.send(:conversation_title, p_hashes.take(2))}"
  puts "Title (2 others): #{ctrl.send(:conversation_title, p_hashes.take(3))}"
  puts "Title (3 others): #{ctrl.send(:conversation_title, p_hashes.take(4))}"
  puts "Title (4 others): #{ctrl.send(:conversation_title, p_hashes.take(5))}"
  puts "Title (Named Group): #{ctrl.send(:conversation_title, p_hashes.take(2), 'Custom Name')}"

ensure
  # Cleanup
  puts "\nCleaning up..."
  [c1, c2, c3].compact.each(&:destroy)
  [u1, u2, u3, u4, u5].each(&:destroy)
  school.destroy
end
