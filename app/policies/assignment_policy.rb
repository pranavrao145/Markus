# Assignment policy class
class AssignmentPolicy < ApplicationPolicy
  default_rule :manage?
  alias_rule :summary?, to: :view?
  alias_rule :stop_batch_tests?, :batch_runs?, to: :manage_tests?
  alias_rule :show?, :peer_review?, to: :student?
  authorize :assessment, :test_run_id, optional: true

  def index?
    true
  end

  def switch?
    true
  end

  def manage?
    check?(:manage_assessments?, role)
  end

  def see_hidden?
    role.instructor? || role.ta? || role.visible_assessments(assessment_id: record.id).exists?
  end

  def stop_test?
    if role.student?
      allowed = check?(:student_tests_enabled?)
      grouping = role.accepted_grouping_for(record.id)
      unless grouping.nil?
        allowed &&= check?(:member?, grouping) &&
          check?(:before_due_date?, grouping)
      end
      allowed && check?(:can_cancel_test?, role, context: { test_run_id: test_run_id })
    else
      check?(:manage_tests?)
    end
  end

  # helper policies

  def view_test_options?
    (check?(:run_tests?, role) && check?(:tests_enabled?)) || (role.student? && check?(:student_tests_enabled?))
  end

  def student_tests_enabled?
    record.enable_student_tests && (record.unlimited_tokens || record.tokens_per_period.positive?)
  end

  def tests_enabled?
    record.enable_test
  end

  def tests_set_up?
    !record.remote_autotest_settings_id.nil?
  end

  def tokens_released?
    !record.token_start_date.nil? && Time.current >= record.token_start_date
  end

  def create_group?
    !check?(:collection_date_passed?) &&
      check?(:students_form_groups?) &&
      check?(:not_yet_in_group?)
  end

  def work_alone?
    details[:group_min] = record.group_min
    record.group_min == 1
  end

  def collection_date_passed?
    record.past_collection_date?(role.section)
  end

  def students_form_groups?
    record.student_form_groups
  end

  def not_yet_in_group?
    !role.has_accepted_grouping_for?(record.id)
  end

  def autogenerate_group_name?
    record.group_name_autogenerated
  end

  def view?
    role.instructor? || role.ta?
  end

  def manage_tests?
    check?(:manage?, with: AutomatedTestPolicy)
  end

  def start_timed_assignment?
    role.student? && (
      (check?(:not_yet_in_group?) &&
        record.section_start_time(role.section) < Time.current &&
        record.section_due_date(role.section) > Time.current &&
        record.group_max == 1) ||
      (!check?(:not_yet_in_group?) &&
        check?(:start_timed_assignment?, role.accepted_grouping_for(record.id), with: GroupingPolicy))
    )
  end

  def starter_file?
    role.instructor? || role.ta?
  end

  def download_starter_file_mappings?
    role.instructor? || role.ta?
  end

  def download_sample_starter_files?
    role.instructor? || role.ta?
  end

  def populate_starter_file_manager?
    role.instructor? || role.ta?
  end

  # needed specifically for TA read-only mode
  def see_starter_files?
    role.instructor? || role.ta?
  end
end
