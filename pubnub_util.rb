class PubnubUtil

  # Constants
  #----------------------------------------------------------------------
  CHANNEL = {
              new_message: "NewMessage", 
              message_read: "MessageRead",
              user_details: "UserDetails",
              group_details: "GroupDetails",
              group_member_action: "GroupMemberAction"
            }


  # Methods
  #----------------------------------------------------------------------
  class << self

    include ApplicationHelper

    ## Initializes Pubnub instance
    def app
      SimpleChat::Application::PubNubApp
    end

    ## PubNub notification for a new message
    def new_message(message, include_alert = true)
      return if message.recipient.blocking?(message.sender)
      channel_name = "#{message[:recipient_id]}_#{CHANNEL[:new_message]}"
      if message.spoof?
        message_data = {
          message: message.api_object3, # is_spoof flag field is added
          sender: message.sender.group? ? message.sender.api_object_group_admin_check(message.recipient) : message.sender.api_object1,
          group_sender: message.group_sender.present? ? message.group_sender.api_object1 : nil,
          spoof_users: message.spoof_users
        }
      else 
        message_data = {
          message: message.api_object2,
          sender: message.sender.group? ? message.sender.api_object_group_admin_check(message.recipient) : message.sender.api_object1,
          group_sender: message.group_sender.present? ? message.group_sender.api_object1 : nil
        }
      end
      message_data[:alert] = Device.alert_text_on_new_message(message) if include_alert
      publish(channel_name, message_data)
    end

    ## PubNub notification for a sent message's read status
    def message_read(message)
      return if message.recipient.blocking?(message.sender)
      channel_name = if message.sender.group?
        return unless (m2 = message.original_group_message).present?
        return if m2[:read_count] > 1
        "#{m2[:sender_id]}_#{CHANNEL[:message_read]}"
      else
        "#{message[:sender_id]}_#{CHANNEL[:message_read]}"
      end
      message_data = {
        read_message: message[:app_message_id],
        sender: message[:sender_id].to_s,
        group_sender: message[:group_sender_id].to_s,
        recipient: message[:recipient_id].to_s
      }
      publish(channel_name, message_data)
    end

    ## PubNub notification when a user details changed
    def user_details(user, server_change=false)
      return if user.group?
      channel_name = "#{user[:id]}_#{CHANNEL[:user_details]}"
      user_data = user.api_object_search
      
      user_data[:server_change] = server_change ? "1" : "0"
      if server_change
        user_data[:server_change] = "1"
        user_data[:offices] = user.api_me_office_list
      else
        user_data[:server_change] = "0"
      end

      publish(channel_name, user_data)
    end

    ## PubNub notification when a group details changed
    def group_details(group)
      return unless group.group?
      channel_name = "#{group[:id]}_#{CHANNEL[:group_details]}"
      group_data = group.api_object1
      publish(channel_name, group_data)
    end

    ## PubNub notification when a user has been added or disabled to and from a group
    def group_member_action(group_member)
      channel_name = "#{group_member[:member_id]}_#{CHANNEL[:group_member_action]}"
      data = {
        group: group_member.group.api_object_group_admin_check(group_member.member),
        member: group_member.api_object
      }
      publish(channel_name, data)
    end

    ## PubNub notification when a user dropped from URGENT GROUPS
    def dropetc_group_member_actions(user_id, group_ids)
      GroupMember.where(member: user_id, group: group_ids).each do |e|
        group_member_action(e)
      end
    end
    handle_asynchronously :dropetc_group_member_actions, priority: 10#, run_at: Proc.new {1.second.from_now}

    ## Publish a message to a channel
    def publish(channel, message)
      # p ">>> >>>X501: #{channel}"
      # p ">>> >>>X502: #{message}"
      app.publish(
        channel: channel,
        message: message,
        store: true
      ) do |envelope|
          p ">>> >>> [PubnubUtil publish on channel: #{channel}] status: #{envelope.status[:code]}"
      end
    end

  end
end