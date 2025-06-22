# Clear existing data
School.destroy_all
User.destroy_all
UserSchoolRole.destroy_all
Account.destroy_all
RequestAccess.destroy_all

# Create a sample school
school = School.create!(
  schoolName: "Test School",
  schoolEmail: "testschool@example.com",
  country: "USA",
  city: "New York",
  province: "NY",
  schoolAddress: { street: "123 Main St", zip: "10001" },
  cash_account: 5000.0
)

puts "✅ Created School: #{school.schoolName}"

# Create a parent user
parent_user = User.create!(
  name: "Jane Smith",
  email: "jane@example.com",
  auth0_id: "auth0|123",
  cash_account: 250.50
)

puts "✅ Created User: #{parent_user.name}"

# Assign user a role in the school
UserSchoolRole.create!(
  user: parent_user,
  school: school,
  role: "Parent"
)

puts "✅ Assigned Role: Parent"

# Create a parent account
account = Account.create!(
  user: parent_user,
  school: school,
  account_type: "parent",
  status: "active",
  balance: 250.50,
  payment_history: [{ amount: 250.50, date: Time.now, type: "credit" }]
)

puts "✅ Created Parent Account with balance: #{account.balance}"

# Create an access request
RequestAccess.create!(
  user: parent_user,
  school: school,
  logged_in_user_email: parent_user.email,
  reason: "Requesting access for my child",
  status: "Pending",
  role: "Parent"
)

puts "✅ Created Access Request"

puts "🎉 Seeding complete!"
