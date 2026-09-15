--
-- Copyright (c) 2026 Red Hat Inc.
--
-- Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with
-- the License. You may obtain a copy of the License at
--
--   http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
-- an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
-- specific language governing permissions and limitations under the License.
--

-- Instance types use their name as their primary key, and compute instance catalog items store instance type defaults
-- as bare strings in the top-level field_definitions array. Extend the existing delete-protection function from
-- migration 90 so an active catalog item cannot retain a dangling spec.instance_type reference. The trigger wiring is
-- unchanged because CREATE OR REPLACE updates the function executed by the existing trigger.
create or replace function check_instance_type_not_in_use() returns trigger as $$
begin
  if exists (
    select 1
    from compute_instances
    where deletion_timestamp = 'epoch'
      and data->'spec'->'instance_type'->>'id' = old.id
  ) then
    raise exception using
      errcode = 'Z0003',
      message = format(
        'cannot delete instance type ''%s'': it is in use by at least one compute instance',
        old.id
      );
  end if;

  if exists (
    select 1
    from compute_instance_templates
    where deletion_timestamp = 'epoch'
      and data->'spec_defaults'->'instance_type'->>'id' = old.id
  ) then
    raise exception using
      errcode = 'Z0003',
      message = format(
        'cannot delete instance type ''%s'': it is in use by at least one compute instance template',
        old.id
      );
  end if;

  if exists (
    select 1
    from compute_instance_catalog_items
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(compute_instance_catalog_items.data->'field_definitions') = 'array'
        then compute_instance_catalog_items.data->'field_definitions'
        else '[]'::jsonb
      end
    ) as fd
    where compute_instance_catalog_items.deletion_timestamp = 'epoch'
      and fd->>'path' = 'spec.instance_type'
      and fd->>'default' = old.name
  ) then
    raise exception using
      errcode = 'Z0003',
      message = format(
        'cannot delete instance type ''%s'': it is in use by at least one compute instance catalog item',
        old.id
      );
  end if;

  return new;
end;
$$ language plpgsql;
