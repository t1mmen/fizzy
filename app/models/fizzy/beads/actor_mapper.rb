module Fizzy
  module Beads
    class ActorMapper
      class MissingAccountError < StandardError; end

      # Maps a Beads actor/author string to a Fizzy User for attribution.
      #
      # Rules (S8 F.2 / fizzy-n3l.2):
      # 1) Identity.email_address == actor → that Identity's User for the account
      # 2) Unique User.name == actor within the account → that User
      # 3) Fallback → system User for the account
      def self.resolve(actor_string, account: Current.account)
        raise MissingAccountError, "account is required" if account.blank?

        actor = actor_string.to_s.strip
        return system_user_for(account) if actor.blank?

        if actor.include?("@")
          email = actor.downcase
          if (identity = Identity.find_by(email_address: email))
            if (user = identity.users.find_by(account: account))
              return user
            end
          end
        end

        by_name = User.where(account: account, name: actor)
        return by_name.first if by_name.one?

        system_user_for(account)
      end

      def self.system_user_for(account)
        if (identity = Identity.find_by(email_address: SystemActor.email))
          if (user = identity.users.find_by(account: account, role: :system))
            return user
          end
        end

        User.where(account: account, role: :system).first ||
          raise(ActiveRecord::RecordNotFound, "No system user found for account=#{account.id}")
      end
    end
  end
end

