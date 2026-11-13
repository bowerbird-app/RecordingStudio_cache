# frozen_string_literal: true

module AccessibleWriteHelpers
  def grant_admin!(user, recording)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: user)
    raise result.error if result.respond_to?(:failure?) && result.failure?

    result
  end
end
