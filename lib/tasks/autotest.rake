
namespace :db do
  desc 'Sets up environment to test the autotester'
  task :autotest => :environment do
    puts 'Set up testing environment for autotest'
    AutotestSetup.new('autotest01')
  end
end

class AutotestSetup

  def initialize(short_id, required_files: ['submission.py'])

    # setup instance variables (mostly paths to directories)
    @assg_short_id = short_id
    root_dir = File.join('db', 'data', 'autotest_files', @assg_short_id)
    script_dir = File.join(root_dir, 'test_scripts')
    @test_scripts = Dir.glob(File.join(script_dir, '*'))
    support_dir = File.join(root_dir, 'test_support_files')
    @test_support_files = Dir.glob(File.join(support_dir, '*'))
    student_dir = File.join(root_dir, 'student_files')
    @student_paths = Dir.glob(File.join(student_dir, '*')).select {|d| File.directory?(d)}
    @req_files = required_files

    @assignment = create_new_assignment


    # clear old file and populate with new files
    clear_old_files
    move_test_script_files

    # setup other elements required for autotesting
    create_marking_scheme
    create_criteria
    create_students
    create_test_files
    collect_submissions
  end

  def clear_old_files
    # remove existing files to create room for new ones
    # remove test scripts
    autotest_dir = File.join(AutomatedTestsClientHelper::ASSIGNMENTS_DIR, @assg_short_id)
    FileUtils.remove_dir(autotest_dir, force: true)
  end

  def move_test_script_files
    # create new directories to put new autotest files into
    test_file_destination = File.join(AutomatedTestsClientHelper::ASSIGNMENTS_DIR, @assg_short_id)
    FileUtils.makedirs test_file_destination

    # copy test scripts and support files into the destination directory
    FileUtils.cp @test_scripts, test_file_destination
    FileUtils.cp @test_support_files, test_file_destination
  end

  def create_marking_scheme
    # make one marking scheme for autotesting in general
    # give all assignments an equal marking weight (1)
    marking_scheme = MarkingScheme.find_or_create_by(name: 'Scheme Autotest')
    marking_weight = MarkingWeight.find_or_create_by(
                      gradable_item_id: @assignment.id,
                      weight: 1,
                      is_assignment: true)
    marking_scheme.marking_weights << marking_weight
  end

  def create_criteria
    # make one criteria of each type
    rubric = RubricCriterion.find_or_create_by(
      name:          "#{@assg_short_id} rubric criterion",
      assignment_id: @assignment.id,
      position:      1,
      max_mark:      10
    )
    rubric.set_default_levels
    rubric.save
    FlexibleCriterion.find_or_create_by(
      name:                   "#{@assg_short_id} flexible criterion",
      assignment_id:          @assignment.id,
      position:               2,
      max_mark:               5,
      assigned_groups_count:  nil
    )
    CheckboxCriterion.find_or_create_by(
      name:                   "#{@assg_short_id} checkbox criterion",
      assignment_id:          @assignment.id,
      position:               3,
      max_mark:               2,
      assigned_groups_count:  nil
    )
  end

  def create_students
    @student_paths.each do |student_path|
      # create group and grouping based on student directory names
      name = File.basename(student_path)
      student = User.add_user(Student, [name, "#{name}_last", "#{name}_first"])
      student.create_group_for_working_alone_student(@assignment.id)
      group = Group.find_by group_name: student.user_name

      # move submission file (only one per student) and commit to repository
      @req_files.each do |filename|
        submission_file_path = File.join(student_path, filename)
        if File.file?(submission_file_path)
          group.access_repo do |repo|
            transaction = repo.get_transaction(student.user_name)
            File.open(submission_file_path, 'r') do |file|
              repo_path = File.join(@assignment.repository_folder, filename)
              transaction.add(repo_path, file.read, '')
            end
            repo.commit(transaction)
          end
        end
      end
    end
  end

  def create_new_assignment
    rule = NoLateSubmissionRule.new
    assignment_stat = AssignmentStat.new
    Assignment.create(
      short_identifier: @assg_short_id,
      description: "Assignment for testing the autotester",
      message: '',
      group_min: 1,
      group_max: 1,
      student_form_groups: false,
      group_name_autogenerated: false,
      group_name_displayed: false,
      repository_folder: @assg_short_id,
      due_date: 1.week.from_now,
      allow_web_submits: true,
      display_grader_names_to_students: false,
      submission_rule: rule,
      assignment_stat: assignment_stat,
      allow_remarks: false,
      enable_test: true,
      tokens_per_period: 0,
      token_start_date: DateTime.now,
      token_period: 1,
      only_required_files: true,
      enable_student_tests: true,
      unlimited_tokens: true
    )
    assignment = Assignment.find_by(short_identifier: @assg_short_id)

    @req_files.each do |filename|
      AssignmentFile.create(
        assignment_id: assignment.id,
        filename: filename
      )
    end
    assignment
  end

  def create_test_files
    # get the criteria from the assignment
    criteria = @assignment.get_criteria
    # create db objects
    @test_scripts.zip(criteria) do |test_script, criterion|
      instructor_run = !File.basename(test_script).include?('student_run_only')
      TestGroup.create(
        assignment: @assignment,
        seq_num: 0,
        file_name: File.basename(test_script),
        description: "",
        run_by_instructors: instructor_run,
        run_by_students: true,
        halts_testing: false,
        display_description: "display_after_submission",
        display_run_status: "display_after_submission",
        display_marks_earned: "display_after_submission",
        display_input: "display_after_submission",
        display_expected_output: "display_after_submission",
        display_actual_output: "display_after_submission",
        timeout: 10,
        criterion: instructor_run ? criterion : nil
      )
    end
    # send files for all hostnames because the
    # autotester uses the names as part of a hash key
    AutotestSpecsJob.perform_now('http://localhost:3000', @assignment.id)
    AutotestSpecsJob.perform_now('http://127.0.0.1:3000', @assignment.id)
    AutotestSpecsJob.perform_now('http://0.0.0.0:3000', @assignment.id)
  end

  def collect_submissions
    # collect the submissions from all groupings for the assignment so they can be autotested
    @assignment.groupings.find_each do |grouping|
      # create new submission for each grouping
      time = @assignment.submission_rule.calculate_collection_time.localtime
      Submission.create_by_timestamp(grouping, time)
      # collect submission
      grouping.is_collected = true
      grouping.save
    end
  end
end
