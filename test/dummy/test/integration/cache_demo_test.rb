# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class CacheDemoTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    load Rails.root.join("db/seeds.rb")
    @user = User.find_by!(email: "admin@admin.com")
    sign_in @user
    @workspace = Workspace.find_by!(name: "Studio Workspace")
    @root = RecordingStudio.root_recording_for(@workspace)
    Rails.cache.clear
  end

  test "home fetch caches api payload and invalidate bumps tree version" do
    get root_path
    assert_response :success
    assert_match "RecordingStudioCache", response.body
    assert_match "api_payload", response.body

    first_version = RecordingStudioCache.tree_version_for(@root)
    assert RecordingStudioCache.exist?(@root, :api_payload)

    get root_path(invalidate: 1)
    assert_redirected_to root_path
    assert_operator RecordingStudioCache.tree_version_for(@root), :>, first_version
    refute RecordingStudioCache.exist?(@root, :api_payload)

    follow_redirect!
    assert_response :success
    assert RecordingStudioCache.exist?(@root, :api_payload)
  end
end
