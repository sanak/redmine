# Redmine - project management software
# Copyright (C) 2006-  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

desc 'Create YAML test fixtures from data in an existing database.
Defaults to development database. Set RAILS_ENV to override.'

module Psych
  module Visitors
    class YAMLTree
      # Override default format
      # https://github.com/ruby/ruby/blob/v3_3_6/ext/psych/lib/psych/visitors/yaml_tree.rb#L484-L490
      def format_time time, utc = time.utc?
        if utc
          time.strftime("%Y-%m-%d %H:%M:%S")
        else
          time.strftime("%Y-%m-%d %H:%M:%S %:z")
        end
      end
    end
  end
end

task :extract_fixtures => :environment do
  dir = ENV['DIR'] || 'tmp/fixtures'
  omit_default_or_nil = ActiveRecord::Type::Boolean.new.cast(ENV.fetch('OMIT_DEFAULT_OR_NIL', 'false'))

  FileUtils.mkdir_p(dir)

  skip_tables = ["schema_migrations", "ar_internal_metadata"]
  ActiveRecord::Base.establish_connection
  (ActiveRecord::Base.connection.tables - skip_tables).each do |table_name|
    i = "000"
    File.open(Rails.root.join(dir, "#{table_name}.yml"), 'w') do |file|
      columns = ActiveRecord::Base.connection.columns(table_name)
      column_names = columns.map(&:name)
      order_columns = column_names.include?('id') ? 'id' : column_names.join(', ')
      sql = "SELECT * FROM #{table_name} ORDER BY #{order_columns}"
      data = ActiveRecord::Base.connection.select_all(sql)
      file.write data.inject({}) { |hash, record|
        # omit default or nil values or format time values
        columns.each do |col|
          if omit_default_or_nil &&
            ((!col.default.nil? && !record[col.name].nil? && record[col.name].to_s == col.default) ||
            col.default.nil? && record[col.name].nil?)
            record.delete(col.name)
            next
          elsif col.type == :datetime && record[col.name].present?
            time = record[col.name].is_a?(String) ? Time.zone.parse(record[col.name]) : record[col.name]
            record[col.name] = time
          end
        end
        hash["#{table_name}_#{i.succ!}"] = record
        hash
      }.to_yaml
    end
  end
end
