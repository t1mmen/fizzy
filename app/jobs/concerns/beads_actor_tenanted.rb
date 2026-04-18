# Serializes the current actor into job data so that jobs run
# within the correct attribution context via Current.with(actor: ...).
#
# Actor resolution is deferred to an around_perform callback so that
# missing actors behave consistently with other tenanted concerns and
# so the CurrentAttributes context is always restored after execution.
module BeadsActorTenanted
  extend ActiveSupport::Concern

  prepended do
    attr_reader :beads_actor
    around_perform :with_beads_actor_context
  end

  def initialize(...)
    super
    @beads_actor = Current.actor
  end

  def serialize
    super.merge({ "beads_actor" => @beads_actor })
  end

  def deserialize(job_data)
    super
    @beads_actor = job_data["beads_actor"]
  end

  private
    def with_beads_actor_context(&block)
      if beads_actor.present?
        Current.with(actor: beads_actor, &block)
      else
        yield
      end
    end
end

