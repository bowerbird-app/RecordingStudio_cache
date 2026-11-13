# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"
require_relative "../support/accessible_write_helpers"

class RootSwitchDropdownTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include AccessibleWriteHelpers

  test "sign in page uses the devise layout and is not squished by the default layout" do
    get new_user_session_path

    assert_response :success
    assert_includes response.body, "admin@admin.com"
    assert_includes response.body, "Password"
    assert_includes response.body, 'data-theme="rounded"'
    refute_includes response.body, "data-recording-studio-default-layout"
    refute_includes response.body, "mt-28"
    refute_includes response.body, "fixed inset-0"
  end

  test "home page renders the root switch dropdown trigger" do
    _user, workspace, _root = sign_in_with_accessible_workspace(
      "root-switch-test@example.com",
      "Dropdown Workspace"
    )

    get root_path

    assert_response :success
    assert_includes response.body, workspace.name
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
  end

  test "root switch page renders with the host default layout" do
    sign_in_with_accessible_workspace(
      "root-switch-page-test@example.com",
      "Switch Page Workspace"
    )

    get "/recording_studio_root_switchable/v1/root_switch?scope=all_workspaces"

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    refute_includes response.body, "flat-pack-sidebar-layout"
  end

  test "switching returns to the current page when it is a valid internal route" do
    _user, _workspace, target_root_recording = sign_in_with_accessible_workspace(
      "root-switch-redirect-test@example.com",
      "Target Workspace"
    )
    sign_in_with_accessible_workspace(
      "root-switch-redirect-test@example.com",
      "Source Workspace"
    )

    patch "/recording_studio_root_switchable/v1/root_switch", params: {
      scope: "all_workspaces",
      root_switch: {
        root_recording_id: target_root_recording.id,
        return_to: "/docs/install"
      }
    }

    assert_redirected_to "/docs/install"
  end

  test "switching falls back to home when return_to is not a valid internal route" do
    _user, _workspace, target_root_recording = sign_in_with_accessible_workspace(
      "root-switch-fallback-test@example.com",
      "Fallback Target Workspace"
    )
    sign_in_with_accessible_workspace(
      "root-switch-fallback-test@example.com",
      "Fallback Source Workspace"
    )

    patch "/recording_studio_root_switchable/v1/root_switch", params: {
      scope: "all_workspaces",
      root_switch: {
        root_recording_id: target_root_recording.id,
        return_to: "/not-a-real-route"
      }
    }

    assert_redirected_to "/"
  end

  private

  def sign_in_with_accessible_workspace(email, workspace_name)
    user = User.find_or_create_by!(email: email) do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end
    Current.actor = user
    sign_in user

    workspace = Workspace.create!(name: workspace_name)
    root = RecordingStudio.root_recording_for(workspace)
    grant_admin!(user, root)
    [ user, workspace, root ]
  end
end
