class ApplicationJob < ActiveJob::Base
  prepend AccountTenanted
  prepend BeadsActorTenanted

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
