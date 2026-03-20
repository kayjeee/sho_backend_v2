#!/bin/bash
# test_teacher_portal.sh
# Tests for Teacher Portal backend implementation

BASE_URL="http://localhost:4000/api/v1"

echo "--- 🚀 STARTING TEACHER PORTAL BACKEND TESTS ---"

# 1. Dashboard Statistics
echo "--- 1. Testing Dashboard Statistics ---"
curl -s -X GET "$BASE_URL/dashboard/overview" | grep -q "success" && echo "✅ Dashboard Overview Success" || echo "❌ Dashboard Overview Failed"

# 2. Schools Search (Multi-strategy lookup)
echo "--- 2. Testing School Lookup ---"
curl -s -X GET "$BASE_URL/schools?search=Test" | grep -q "success" && echo "✅ School Search Success" || echo "❌ School Search Failed"

# 3. Invitations Verification (Public)
echo "--- 3. Testing Public Invitation Verification ---"
# We expect a 404 since we don't have a valid token in this test, but it should return a JSON error, not a crash
curl -s -X GET "$BASE_URL/invitations/invalid-token/verify_with_details" | grep -q "error" && echo "✅ Invitation Verification (Invalid Token) handled" || echo "❌ Invitation Verification Failed"

# 4. Teacher Grade Assignments
echo "--- 4. Testing Teacher Grade Assignments ---"
curl -s -X GET "$BASE_URL/teacher_grade_assignments" | grep -q "success" && echo "✅ Teacher Grade Assignments Success" || echo "❌ Teacher Grade Assignments Failed"

# 5. Learner Invitations
echo "--- 5. Testing Learner Invitations ---"
curl -s -X GET "$BASE_URL/learner_invitations/pending" | grep -q "success" && echo "✅ Pending Learner Invitations Success" || echo "❌ Pending Learner Invitations Failed"

# 6. Teacher Invitations
echo "--- 6. Testing Teacher Invitations ---"
curl -s -X GET "$BASE_URL/teacher_invitations/pending" | grep -q "success" && echo "✅ Pending Teacher Invitations Success" || echo "❌ Pending Teacher Invitations Failed"

echo "--- 🏁 TESTS COMPLETED ---"
