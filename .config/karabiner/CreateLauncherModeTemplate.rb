#!/usr/bin/env ruby

# You can generate json by executing the following command on Terminal.
#
# $ ruby ./CreateLauncherModeTemplate.json.rb
#

# Parameters

def parameters
    {
      :simultaneous_threshold_milliseconds => 500,
      :trigger_key => 'right_option',
    }
  end

  ############################################################

  require 'json'

  def main
    data = {
      'title' => 'O-Launcher',
      'rules' => [
        {
          'description' => 'O-Launcher',
          'manipulators' => [
            generate_launcher_mode('a', [], [{ 'shell_command' => "open -a 'Activity Monitor.app'" }]),
            generate_launcher_mode('v', [], [{ 'shell_command' => "open -a 'Visual Studio Code.app'" }]),
            generate_launcher_mode('o', [], [{ 'shell_command' => "open -a 'Obsidian.app'" }]),
            generate_launcher_mode('t', [], [{ 'shell_command' => "open -a 'iTerm.app'" }]),
            generate_launcher_mode('m', [], [{ 'shell_command' => "open -a 'Mail.app'" }]),
            generate_launcher_mode('p', [], [{ 'shell_command' => "open -a 'Adobe Acrobat.app'" }]),
            generate_launcher_mode('r', [], [{ 'shell_command' => "open -a 'Reminders.app'" }]),
            generate_launcher_mode('s', [], [{ 'shell_command' => "open -a 'Safari.app'" }]),
            generate_launcher_mode('c', [], [{ 'shell_command' => "open -a 'Calendar.app'" }]),
            generate_launcher_mode('l', [], [{ 'shell_command' => "open -a 'Slack.app'" }]),
            generate_launcher_mode('u', [], [{ 'shell_command' => "open -a 'Music.app'" }]),
            generate_launcher_mode('g', [], [{ 'shell_command' => "open -a 'Messages.app'" }]),
            generate_launcher_mode('d', [], [{ 'shell_command' => "open -a 'Discord.app'" }]),
            generate_launcher_mode('n', [], [{ 'shell_command' => "open -a 'Notes.app'" }]),
            generate_launcher_mode('z', [], [{ 'shell_command' => "open -a 'Zotero.app'" }]),
            generate_launcher_mode('w', [], [{ 'shell_command' => "open -a 'Microsoft Word.app'" }]),
            generate_launcher_mode('f', [], [{ 'shell_command' => "open -a 'Finder.app'" }])

          ].flatten,
        },
      ],
    }

    puts JSON.pretty_generate(data)
  end

  def generate_launcher_mode(from_key_code, mandatory_modifiers, to)
    data = []

    ############################################################

    h = {
      'type' => 'basic',
      'from' => {
        'key_code' => from_key_code,
        'modifiers' => {
          'mandatory' => mandatory_modifiers,
          'optional' => [
            'any',
          ],
        },
      },
      'to' => to,
      'conditions' => [
        {
          'type' => 'variable_if',
          'name' => 'launcher_mode',
          'value' => 1,
        },
      ],
    }

    data << h

    ############################################################

    h = {
      'type' => 'basic',
      'from' => {
        'simultaneous' => [
          {
            'key_code' => parameters[:trigger_key],
          },
          {
            'key_code' => from_key_code,
          },
        ],
        'simultaneous_options' => {
          'key_down_order' => 'strict',
          'key_up_order' => 'strict_inverse',
          'to_after_key_up' => [
            {
              'set_variable' => {
                'name' => 'launcher_mode',
                'value' => 0,
              },
            },
          ],
        },
        'modifiers' => {
          'mandatory' => mandatory_modifiers,
          'optional' => [
            'any',
          ],
        },
      },
      'to' => [
        {
          'set_variable' => {
            'name' => 'launcher_mode',
            'value' => 1,
          },
        },
      ].concat(to),
      'parameters' => {
        'basic.simultaneous_threshold_milliseconds' => parameters[:simultaneous_threshold_milliseconds],
      },
    }

    data << h

    ############################################################

    data
  end

  main
