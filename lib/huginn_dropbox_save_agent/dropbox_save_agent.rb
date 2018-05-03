# frozen_string_literal: true

module Agents
  ##
  # = Huginn Dropbox Save Agent
  #
  class DropboxSaveAgent < Agent
    include DropboxConcern
    include FileHandling

    OVERWRITE_OFF = 'off'
    OVERWRITE_ON = 'on'
    OVERWRITE_RENAME = 'rename'

    OVERWRITE_MODES = [OVERWRITE_OFF, OVERWRITE_ON, OVERWRITE_RENAME].freeze

    RENAME_SUFFIX_REGEX = /_(\d+)\z/

    cannot_be_scheduled!
    no_bulk_receive!
    consumes_file_pointer!

    description <<-MD
      Add a Agent description here
    MD

    def default_options
      {
        path: '/huginn',
        filename: 'file',
        overwrite_mode: OVERWRITE_OFF
      }
    end

    def validate_options
      errors.add(:base, 'path must be present') unless options['path'].present?
      errors.add(:base, 'filename must be present') unless options['filename'].present?
      errors.add(:base, "overwrite_mode must be one of #{OVERWRITE_MODES.inspect}") unless OVERWRITE_MODES.include?(options['overwrite_mode'])
    end

    def working?
      received_event_without_error?
    end

    def receive(incoming_events)
      incoming_events.each { |event| handle_event event }
    end

    private

    def handle_event(event)
      io = get_io(event)
      return unless io.present?

      if file_exists?
        handle_overwrite(io)
      else
        save_file(io)
      end
    end

    def save_file(io, filename: full_file_path)
      dropbox.upload(filename, io.read)
    end

    def file_exists?
      !!dropbox.find(full_file_path)
    rescue Dropbox::API::Error => e
      e.message.include?('409') ? false : raise(e)
    end

    def handle_overwrite(io)
      case interpolated['overwrite_mode']
      when OVERWRITE_OFF
        nil
      when OVERWRITE_ON
        save_file(io)
      when OVERWRITE_RENAME
        save_file(io, filename: full_file_path(increment: true))
      end
    end

    def full_file_path(increment: false)
      filename = increment ? next_filename : interpolated['filename']

      path = interpolated['path']
      path = "/#{path}" unless path.start_with?('/')

      [path, filename].join('/')
    end

    def next_filename
      current_name = interpolated['filename']

      number_match_data = current_name.match(RENAME_SUFFIX_REGEX)

      if number_match_data.present?
        next_number = number_match_data[1].to_i + 1
        "#{current_name}_#{next_number}"
      else
        "#{current_name}_1"
      end
    end
  end
end
