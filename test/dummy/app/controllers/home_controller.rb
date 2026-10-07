# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    @workspace = Workspace.find_by(name: "Studio Workspace") || Workspace.order(:created_at).first
    @root = @workspace && RecordingStudio.root_recording_for(@workspace)
    return unless @root

    @cache_key = RecordingStudioCache.key_for(@root, :api_payload)
    @tree_version = RecordingStudioCache.tree_version_for(@root)
    @payload = RecordingStudioCache.fetch(@root, :api_payload) do
      {
        recording_id: @root.id,
        workspace: @workspace.name,
        cached_at: Time.current.iso8601,
        note: "App-side Rails.cache payload (not CDN/Artifacts)"
      }
    end

    return unless params[:invalidate] == "1"

    RecordingStudioCache.invalidate_tree!(@root)
    redirect_to root_path, notice: "Tree cache version bumped"
  end
end
