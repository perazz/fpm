!> Define tests for the `fpm_backend` module (build scheduling)
module test_backend
    use testsuite, only : new_unittest, unittest_t, error_t, test_failed
    use test_module_dependencies, only: operator(.in.)
    use fpm_filesystem, only: exists, mkdir, get_temp_filename
    use fpm_targets, only: build_target_t, build_target_ptr, &
                            FPM_TARGET_OBJECT, FPM_TARGET_ARCHIVE, FPM_TARGET_SHARED, &
                           add_target, add_dependency
    use fpm_backend, only: sort_target, schedule_targets
    use fpm_strings, only: string_t
    use fpm_environment, only: OS_LINUX
    use fpm_compile_commands, only: compile_command_t, compile_command_table_t
    implicit none
    private

    public :: collect_backend

contains


    !> Collect all exported unit tests
    subroutine collect_backend(testsuite)

        !> Collection of tests
        type(unittest_t), allocatable, intent(out) :: testsuite(:)

        testsuite = [ &
            & new_unittest("target-sort", test_target_sort), &
            & new_unittest("target-sort-skip-all", test_target_sort_skip_all), &
            & new_unittest("target-sort-rebuild-all", test_target_sort_rebuild_all), &
            & new_unittest("target-shared-sort", test_target_shared), &
            & new_unittest("schedule-targets", test_schedule_targets), &
            & new_unittest("schedule-targets-empty", test_schedule_empty), &
            & new_unittest("serialize-compile-commands", compile_commands_roundtrip), &
            & new_unittest("compile-commands-write", compile_commands_register_from_cmd), &
            & new_unittest("compile-commands-register-string", compile_commands_register_from_string) &
            ]

    end subroutine collect_backend


    !> Check scheduling of objects with dependencies
    subroutine test_target_sort(error)

        !> Error handling
        type(error_t), allocatable, intent(out) :: error

        type(build_target_ptr), allocatable :: targets(:)

        integer :: i

        targets = new_test_package()

        ! Perform depth-first topological sort of targets
        do i=1,size(targets)

            call sort_target(targets(i)%ptr)

        end do

        ! Check target states: all targets scheduled
        do i=1,size(targets)

            if (.not.targets(i)%ptr%touched) then
                call test_failed(error,"Target touched flag not set")
                return
            end if

            if (.not.targets(i)%ptr%sorted) then
                call test_failed(error,"Target sort flag not set")
                return
            end if

            if (targets(i)%ptr%skip) then
                call test_failed(error,"Target skip flag set incorrectly")
                return
            end if

            if (targets(i)%ptr%schedule < 0) then
                call test_failed(error,"Target schedule not set")
                return
            end if

        end do

        ! Check all objects sheduled before library
        do i=2,size(targets)

            if (targets(i)%ptr%schedule >= targets(1)%ptr%schedule) then
                call test_failed(error,"Object dependency scheduled after dependent library target")
                return
            end if

        end do

        ! Check target 4 schedule before targets 2 & 3
        do i=2,3
            if (targets(4)%ptr%schedule >= targets(i)%ptr%schedule) then
                call test_failed(error,"Object dependency scheduled after dependent object target")
                return
            end if
        end do

    end subroutine test_target_sort



    !> Check incremental rebuild for existing archive
    !>  all object sources are unmodified: all objects should be skipped
    subroutine test_target_sort_skip_all(error)

        !> Error handling
        type(error_t), allocatable, intent(out) :: error

        type(build_target_ptr), allocatable :: targets(:)

        integer :: fh, i

        targets = new_test_package()

        do i=2,size(targets)

            ! Mimick unmodified sources
            allocate(targets(i)%ptr%source)
            targets(i)%ptr%source%digest = i
            targets(i)%ptr%digest_cached = i

        end do

        ! Mimick archive already exists
        open(newunit=fh,file=targets(1)%ptr%output_file,status="unknown")
        close(fh)

        ! Perform depth-first topological sort of targets
        do i=1,size(targets)

            call sort_target(targets(i)%ptr)

        end do

        ! Check target states: all targets skipped
        do i=1,size(targets)

            if (.not.targets(i)%ptr%touched) then
                call test_failed(error,"Target touched flag not set")
                return
            end if

            if (targets(i)%ptr%sorted) then
                call test_failed(error,"Target sort flag set incorrectly")
                return
            end if

            if (.not.targets(i)%ptr%skip) then
                call test_failed(error,"Target skip flag set incorrectly")
                return
            end if

        end do

    end subroutine test_target_sort_skip_all


    !> Check incremental rebuild for existing archive
    !>  all but lowest source modified: all objects should be rebuilt
    subroutine test_target_sort_rebuild_all(error)

        !> Error handling
        type(error_t), allocatable, intent(out) :: error

        type(build_target_ptr), allocatable :: targets(:)

        integer :: fh, i

        targets = new_test_package()

        do i=2,3

            ! Mimick unmodified sources
            allocate(targets(i)%ptr%source)
            targets(i)%ptr%source%digest = i
            targets(i)%ptr%digest_cached = i

        end do

        ! Mimick archive already exists
        open(newunit=fh,file=targets(1)%ptr%output_file,status="unknown")
        close(fh)

        ! Perform depth-first topological sort of targets
        do i=1,size(targets)

            call sort_target(targets(i)%ptr)

        end do

        ! Check target states: all targets scheduled
        do i=1,size(targets)

            if (.not.targets(i)%ptr%sorted) then
                call test_failed(error,"Target sort flag not set")
                return
            end if

            if (targets(i)%ptr%skip) then
                call test_failed(error,"Target skip flag set incorrectly")
                return
            end if

        end do

    end subroutine test_target_sort_rebuild_all


    !> Check construction of target queue and schedule
    subroutine test_schedule_targets(error)

        !> Error handling
        type(error_t), allocatable, intent(out) :: error

        type(build_target_ptr), allocatable :: targets(:)

        integer :: i, j
        type(build_target_ptr), allocatable :: queue(:)
        integer, allocatable :: schedule_ptr(:)

        targets = new_test_package()

        ! Perform depth-first topological sort of targets
        do i=1,size(targets)

            call sort_target(targets(i)%ptr)

        end do

        ! Construct build schedule queue
        call schedule_targets(queue, schedule_ptr, targets)

        ! Check all targets enqueued
        do i=1,size(targets)

            if (.not.(targets(i)%ptr.in.queue)) then

                call test_failed(error,"Target not found in build queue")
                return

            end if

        end do

        ! Check schedule structure
        if (schedule_ptr(1) /= 1) then

            call test_failed(error,"schedule_ptr(1) does not point to start of the queue")
            return

        end if

        if (schedule_ptr(size(schedule_ptr)) /= size(queue)+1) then

            call test_failed(error,"schedule_ptr(end) does not point to end of the queue")
            return

        end if

        do i=1,size(schedule_ptr)-1

            do j=schedule_ptr(i),(schedule_ptr(i+1)-1)

                if (queue(j)%ptr%schedule /= i) then

                    call test_failed(error,"Target scheduled in the wrong region")
                    return

                end if

            end do

        end do

    end subroutine test_schedule_targets


    !> Check construction of target queue and schedule
    !>  when there's nothing to do (all targets skipped)
    subroutine test_schedule_empty(error)

        !> Error handling
        type(error_t), allocatable, intent(out) :: error

        type(build_target_ptr), allocatable :: targets(:)

        integer :: i
        type(build_target_ptr), allocatable :: queue(:)
        integer, allocatable :: schedule_ptr(:)

        targets = new_test_package()

        do i=1,size(targets)

            targets(i)%ptr%skip = .true.

        end do

        ! Perform depth-first topological sort of targets
        do i=1,size(targets)

            call sort_target(targets(i)%ptr)

        end do

        ! Construct build schedule queue
        call schedule_targets(queue, schedule_ptr, targets)

        ! Check queue is empty
        if (size(queue) > 0) then

            call test_failed(error,"Expecting an empty build queue, but not empty")
            return

        end if

        ! Check schedule loop is not entered
        do i=1,size(schedule_ptr)-1

            call test_failed(error,"Attempted to run an empty schedule")
            return

        end do

    end subroutine test_schedule_empty


    !> Helper to generate target objects with dependencies
    function new_test_package() result(targets)

        type(build_target_ptr), allocatable :: targets(:)
        integer :: i

        call add_target(targets,'test-package',FPM_TARGET_ARCHIVE,get_temp_filename())

        call add_target(targets,'test-package',FPM_TARGET_OBJECT,get_temp_filename())

        call add_target(targets,'test-package',FPM_TARGET_OBJECT,get_temp_filename())

        call add_target(targets,'test-package',FPM_TARGET_OBJECT,get_temp_filename())

        ! Library depends on all objects
        call add_dependency(targets(1)%ptr,targets(2)%ptr)
        call add_dependency(targets(1)%ptr,targets(3)%ptr)
        call add_dependency(targets(1)%ptr,targets(4)%ptr)

        ! Inter-object dependency
        !  targets 2 & 3 depend on target 4
        call add_dependency(targets(2)%ptr,targets(4)%ptr)
        call add_dependency(targets(3)%ptr,targets(4)%ptr)

    end function new_test_package

    subroutine compile_commands_roundtrip(error)
        
        !> Error handling
        type(error_t), allocatable, intent(out) :: error
        
        type(compile_command_t) :: cmd
        type(compile_command_table_t) :: cc
        integer :: i
        
        call cmd%test_serialization('compile_command: empty', error)
        if (allocated(error)) return
        
        cmd = compile_command_t(directory = string_t("/test/dir"), &
                                arguments = [string_t("gfortran"), &
                                             string_t("-c"), string_t("main.f90"), &
                                             string_t("-o"), string_t("main.o")], &
                                file = string_t("main.f90"))
        
        call cmd%test_serialization('compile_command: non-empty', error)
        if (allocated(error)) return       
       
        call cc%test_serialization('compile_command_table: empty', error)
        if (allocated(error)) return
        
        do i=1,10
           call cc%register(cmd,error)
           if (allocated(error)) return
        end do
        
        call cc%test_serialization('compile_command_table: non-empty', error)
        if (allocated(error)) return        
         
    end subroutine compile_commands_roundtrip

    subroutine compile_commands_register_from_cmd(error)
        type(error_t), allocatable, intent(out) :: error
        
        type(compile_command_table_t) :: table
        type(compile_command_t) :: cmd
        integer :: i

        cmd = compile_command_t(directory = string_t("/src"), &
                                arguments = [string_t("gfortran"), &
                                             string_t("-c"), string_t("example.f90"), &
                                             string_t("-o"), string_t("example.o")], &
                                file = string_t("example.f90"))

        call table%register(cmd, error)
        if (allocated(error)) return

        if (.not.allocated(table%command)) then 
            call test_failed(error, "Command table not allocated after registration")
            return 
        endif
            
        if (size(table%command) /= 1) then 
            call test_failed(error, "Expected one registered command")
            return
        endif
        
        if (table%command(1)%file%s /= "example.f90") then 
            call test_failed(error, "Registered file mismatch")
            return
        endif
        
    end subroutine compile_commands_register_from_cmd

    subroutine compile_commands_register_from_string(error)
        type(error_t), allocatable, intent(out) :: error

        type(compile_command_table_t) :: table
        character(len=*), parameter :: cmd_line = "gfortran -c example.f90 -o example.o"

        ! Register a raw command line string
        call table%register(cmd_line, OS_LINUX, error)
        if (allocated(error)) return

        if (.not.allocated(table%command)) then
            call test_failed(error, "Command table not allocated after string registration")
            return
        end if

        if (size(table%command) /= 1) then
            call test_failed(error, "Expected one registered command after string registration")
            return
        end if

        if (.not.allocated(table%command(1)%arguments)) then
            call test_failed(error, "Command arguments not allocated")
            return
        end if

        if (size(table%command(1)%arguments) /= 5) then
            call test_failed(error, "Wrong number of parsed arguments, should be 5")
            return
        end if

        if (table%command(1)%arguments(1)%s /= "gfortran") then
            call test_failed(error, "Expected 'gfortran' as first argument")
            return
        end if

        if (table%command(1)%arguments(3)%s /= "example.f90") then
            call test_failed(error, "Expected 'example.f90' as third argument")
            return
        end if

    end subroutine compile_commands_register_from_string

    !> Check sorting and scheduling for shared library targets
    subroutine test_target_shared(error)

        !> Error handling
        type(error_t), allocatable, intent(out) :: error

        type(build_target_ptr), allocatable :: targets(:)
        integer :: i

        ! Create a new test package with a shared library
        call add_target(targets, 'test-shared', FPM_TARGET_SHARED, get_temp_filename())
        call add_target(targets, 'test-shared', FPM_TARGET_OBJECT, get_temp_filename())
        call add_target(targets, 'test-shared', FPM_TARGET_OBJECT, get_temp_filename())

        ! Shared library depends on the two object files
        call add_dependency(targets(1)%ptr, targets(2)%ptr)
        call add_dependency(targets(1)%ptr, targets(3)%ptr)

        ! Perform topological sort
        do i = 1, size(targets)
            call sort_target(targets(i)%ptr)
        end do

        ! Check scheduling and flags
        do i = 1, size(targets)
            if (.not.targets(i)%ptr%touched) then
                call test_failed(error, "Shared: Target not touched")
                return
            end if
            if (.not.targets(i)%ptr%sorted) then
                call test_failed(error, "Shared: Target not sorted")
                return
            end if
            if (targets(i)%ptr%skip) then
                call test_failed(error, "Shared: Target incorrectly skipped")
                return
            end if
        end do

        ! Check dependencies scheduled before the shared lib
        if (targets(2)%ptr%schedule >= targets(1)%ptr%schedule) then
            call test_failed(error, "Shared: Object 2 scheduled after shared lib")
            return
        end if
        if (targets(3)%ptr%schedule >= targets(1)%ptr%schedule) then
            call test_failed(error, "Shared: Object 3 scheduled after shared lib")
            return
        end if

    end subroutine test_target_shared




end module test_backend
