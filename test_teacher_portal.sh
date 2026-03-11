#!/bin/bash

# ==============================================================================
# TEACHER PORTAL API TEST SCRIPT
# This script tests all key endpoints for the Teacher Portal backend implementation.
# Usage: ./test_teacher_portal.sh [BASE_URL]
# Default BASE_URL: http://localhost:4000
# Requirements: curl, jq
# ==============================================================================

BASE_URL=${1:-"http://localhost:4000"}
API_V1="$BASE_URL/api/v1"

echo "🚀 Starting Teacher Portal API tests at $BASE_URL"
echo "---------------------------------------------------"

# Helper for testing endpoints
test_endpoint() {
    local method=$1
    local endpoint=$2
    local description=$3
    local data=$4

    echo "Testing [$method] $endpoint - $description"
    if [ "$method" == "GET" ]; then
        curl -s -X GET "$API_V1$endpoint" | jq .
    else
        curl -s -X $method "$API_V1$endpoint" \
             -H "Content-Type: application/json" \
             -d "$data" | jq .
    fi
    echo "---------------------------------------------------"
}

# =========================================================
# 1. SCHOOLS & BROWSER (SchoolsController)
# =========================================================
echo "🏫 1. SCHOOLS & BROWSER TESTS"
test_endpoint "GET" "/schools" "List all schools"
test_endpoint "GET" "/schools?search=Test&page=1&limit=5" "Search schools with pagination"
test_endpoint "GET" "/schools/search?query=New+School" "Check school name availability"

# =========================================================
# 2. TEACHER DASHBOARD (DashboardController)
# =========================================================
echo "📊 2. TEACHER DASHBOARD TESTS"
test_endpoint "GET" "/dashboard/overview" "Dashboard overview (general)"
test_endpoint "GET" "/dashboard/overview?teacher_id=60d5f9b4c9e77b001f8e4d3a" "Dashboard overview (specific teacher)"
test_endpoint "GET" "/dashboard/learner_statistics" "Learner statistics"
test_endpoint "GET" "/dashboard/school_statistics" "School statistics"
test_endpoint "GET" "/dashboard/assessment_statistics" "Assessment statistics"
test_endpoint "GET" "/dashboard/grade_statistics" "Grade-by-grade statistics"

# =========================================================
# 3. TEACHER GRADE ASSIGNMENTS (TeacherGradeAssignmentsController)
# =========================================================
echo "📋 3. TEACHER GRADE ASSIGNMENT TESTS"
test_endpoint "GET" "/teacher_grade_assignments" "List all assignments"
test_endpoint "GET" "/teacher_grade_assignments/by_teacher/60d5f9b4c9e77b001f8e4d3a" "Assignments by teacher"
test_endpoint "GET" "/teacher_grade_assignments/by_school/60d5f9b4c9e77b001f8e4d3a" "Assignments by school"

# Example POST for creation (Requires valid IDs)
# test_endpoint "POST" "/teacher_grade_assignments" "Create teacher assignment" \
# '{"teacher_grade_assignment": {"teacher_id": "60d...", "grade_id": "60d...", "school_id": "60d...", "role_type": "primary"}}'

# =========================================================
# 4. LEARNER INVITATIONS (LearnerInvitationsController)
# =========================================================
echo "📨 4. LEARNER INVITATION TESTS"
test_endpoint "GET" "/learner_invitations" "List all learner invitations"
test_endpoint "GET" "/learner_invitations/pending" "List pending learner invitations"
test_endpoint "GET" "/learner_invitations/expired" "List expired learner invitations"
test_endpoint "GET" "/learner_invitations/by_grade/60d5f9b4c9e77b001f8e4d3a" "Invitations by grade"

# =========================================================
# 5. TEACHER INVITATIONS (TeacherInvitationsController)
# =========================================================
echo "📧 5. TEACHER INVITATION TESTS"
test_endpoint "GET" "/teacher_invitations" "List all teacher invitations"
test_endpoint "GET" "/teacher_invitations/pending" "List pending teacher invitations"
test_endpoint "GET" "/teacher_invitations/by_school/60d5f9b4c9e77b001f8e4d3a" "Invitations by school"

# =========================================================
# 6. GRADE MANAGEMENT & COMMUNICATIONS (GradesController)
# =========================================================
echo "🎒 6. GRADE MANAGEMENT TESTS"
test_endpoint "GET" "/grades/60d5f9b4c9e77b001f8e4d3a/learners" "List learners in a grade"
test_endpoint "GET" "/grades/60d5f9b4c9e77b001f8e4d3a/teachers" "List teachers in a grade"
test_endpoint "GET" "/grades/60d5f9b4c9e77b001f8e4d3a/stats" "Get grade-specific statistics"

# Example POST for inviting (Requires valid IDs)
# test_endpoint "POST" "/grades/60d.../invite_learner" "Invite a parent/learner" \
# '{"invitation": {"recipient_phone_number": "0812345678", "parent_name": "John Doe", "learner_number": "STD123"}}'

echo "🏁 Teacher Portal API tests completed!"
echo "Note: Creation and action-based tests (POST/PATCH) require valid BSON IDs from your database."
