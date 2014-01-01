module my_radex

use phy_const
!use data_struct
use trivials
use statistic_equilibrium
!use chemistry

implicit none

integer, parameter :: ndim_cfg_vec = 100

type :: type_rdxx_cfg
  character(len=128) :: dir_transition_rates = './'
  character(len=128) :: dir_save = './'
  character(len=128) :: filename_molecule = '12C16O_H2.dat'
  character(len=128) :: filename_save = 'output.dat'
  !
  double precision freqmin, freqmax
  !
  double precision max_evol_time
  real max_code_run_time
  !
  character(len=16)  :: geotype = ''
  double precision Tcmb
  !
  logical :: provideLength = .false.
  double precision length_scale
  !
  double precision, dimension(ndim_cfg_vec) :: &
    Tkin, dv, Ncol_x, n_x, &
    n_H2, n_HI, n_oH2, n_pH2, n_Hplus, n_E, n_He   
  integer nTkin, ndv, nn_x, nNcol_x, ndens ! Vector sizes
  integer iTkin, idv, in_x, iNcol_x, idens ! Loop indices
  integer fU
end type type_rdxx_cfg

type(type_rdxx_cfg) :: rdxx_cfg

namelist /rdxx_configure/ rdxx_cfg


contains


subroutine do_my_radex
  integer i, itot, ntot
  integer iTkin, idv, in_x, iNcol_x, idens
  double precision fup, flow, gup, glow, Tex, Tr, flux_CGS, flux_K_km_s
  double precision Inu_t, tau, t1, t2
  integer flag_good
  !
  call openFileSequentialWrite(rdxx_cfg%fU, &
    combine_dir_filename(rdxx_cfg%dir_save, &
    rdxx_cfg%filename_save), 999, 1)
  write(rdxx_cfg%fU, '(2A5, A12, 2A15, 9A12, 2A7, &
            &3A12, A2)') &
    '! iup', 'ilow', 'Eup', 'freq', 'lam', 'Tex', 'tau', 'Tr', &
    'fup', 'flow', 'flux_K', 'flux', 'beta', &
    'Jnu', 'gup', 'glow', 'Aul', 'Bul', 'Blu', 'q'
  write(rdxx_cfg%fU, '(2A5, A12, 2A15, 9A12, 2A7, &
            &3A12, A2)') &
    '!    ', '  ', 'K', 'Hz', 'micron', 'K', '', 'K', &
    '   ', '    ', 'K km/s', 'erg/cm2/s', '    ', &
    '...', '   ', '    ', '...', '...', '...', ''
  !
  ! Big loop
  !
  itot = 0
  ntot = rdxx_cfg%nTkin * rdxx_cfg%ndv * rdxx_cfg%nn_x * &
         rdxx_cfg%nNcol_x * rdxx_cfg%ndens
  !
  do iTkin=1, rdxx_cfg%nTkin
  do idv=1, rdxx_cfg%ndv
  do in_x=1, rdxx_cfg%nn_x
  do iNcol_x=1, rdxx_cfg%nNcol_x
  do idens=1, rdxx_cfg%ndens
    !
    itot = itot + 1
    !
    rdxx_cfg%iTkin   = iTkin
    rdxx_cfg%idv     = idv
    rdxx_cfg%in_x    = in_x
    rdxx_cfg%iNcol_x = iNcol_x
    rdxx_cfg%idens   = idens
    !
    write(rdxx_cfg%fU, '("!", I6, "/", I6, A, 5I5, " / ", 5I5, 2X, A)') &
      itot, ntot, ': ', &
      rdxx_cfg%iTkin, rdxx_cfg%idv, rdxx_cfg%in_x, &
      rdxx_cfg%iNcol_x, rdxx_cfg%idens, &
      rdxx_cfg%nTkin, rdxx_cfg%ndv, rdxx_cfg%nn_x, &
      rdxx_cfg%nNcol_x, rdxx_cfg%ndens, &
      'Loop order: Tkin, dv, n_x, Ncol_x, dens'
    write(rdxx_cfg%fU, '(3("!", ES12.4, " =", A8/), ("!", ES12.4, " =", A8))') &
      rdxx_cfg%Tkin(rdxx_cfg%iTkin), 'Tkin', &
      rdxx_cfg%dv(rdxx_cfg%idv), 'dv', &
      rdxx_cfg%n_x(rdxx_cfg%in_x), 'n_x', &
      rdxx_cfg%Ncol_x(rdxx_cfg%iNcol_x), 'Ncol_x'
    !
    write(*, '("!", I6, "/", I6, A, 5I5, " / ", 5I5, 2X, A)') &
      itot, ntot, ': ', &
      rdxx_cfg%iTkin, rdxx_cfg%idv, rdxx_cfg%in_x, &
      rdxx_cfg%iNcol_x, rdxx_cfg%idens, &
      rdxx_cfg%nTkin, rdxx_cfg%ndv, rdxx_cfg%nn_x, &
      rdxx_cfg%nNcol_x, rdxx_cfg%ndens, &
      'Loop order: Tkin, dv, n_x, Ncol_x, dens'
    write(*, '(3("!", ES12.4, " =", A8/), ("!", ES12.4, " =", A8))') &
      rdxx_cfg%Tkin(rdxx_cfg%iTkin), 'Tkin', &
      rdxx_cfg%dv(rdxx_cfg%idv), 'dv', &
      rdxx_cfg%n_x(rdxx_cfg%in_x), 'n_x', &
      rdxx_cfg%Ncol_x(rdxx_cfg%iNcol_x), 'Ncol_x'
    !
    call my_radex_prepare_molecule
    call statistic_equil_solve
    !
    if (statistic_equil_params%is_good) then
      flag_good = 1
    else
      flag_good = 0
    end if
    !
    do i=1, a_mol_using%rad_data%n_transition
      associate(r => a_mol_using%rad_data%list(i))
        if ((r%freq .lt. rdxx_cfg%freqmin) .or. &
            (r%freq .gt. rdxx_cfg%freqmax)) then
          cycle
        end if
        !
        fup  = a_mol_using%f_occupation(r%iup)
        flow = a_mol_using%f_occupation(r%ilow)
        gup  = a_mol_using%level_list(r%iup)%weight
        glow = a_mol_using%level_list(r%ilow)%weight
        Tex = -(r%Eup - r%Elow) / log(fup*glow / (flow*gup))
        !
        tau = r%tau
        t1 = exp(-tau)
        if (abs(tau) .lt. 1D-6) then
          t2 = tau
        else
          t2 = 1D0 - t1
        end if
        Inu_t = planck_B_nu(Tex, r%freq) * t2 + t1 * r%J_cont
        !
        Tr = (Inu_t - r%J_cont) * phy_SpeedOfLight_CGS**2 / &
          (2D0 * r%freq**2 * phy_kBoltzmann_CGS)
        flux_K_km_s = Tr * a_mol_using%dv / 1D5 * phy_GaussFWHM_c
        flux_CGS = (Inu_t - r%J_cont) * &
          a_mol_using%dv * r%freq / phy_SpeedOfLight_CGS
        write(rdxx_cfg%fU, '(2I5, F12.4, 2ES15.7, 9ES12.3, 2F7.1, &
                  &3ES12.3, I2)') &
          r%iup-1, r%ilow-1, r%Eup, r%freq, r%lambda, Tex, r%tau, Tr, &
          fup, flow, flux_K_km_s, flux_CGS, r%beta, &
          r%J_ave, gup, glow, r%Aul, r%Bul, r%Blu, flag_good
      end associate
    end do
  end do
  end do
  end do
  end do
  end do
  !
  close(rdxx_cfg%fU)
  nullify(a_mol_using)
end subroutine do_my_radex


subroutine my_radex_prepare_molecule
  integer i
  !
  a_mol_using%geotype = rdxx_cfg%geotype ! Geometric type
  !
  a_mol_using%Tkin = rdxx_cfg%Tkin(rdxx_cfg%iTkin) ! K
  a_mol_using%dv = rdxx_cfg%dv(rdxx_cfg%idv) ! cm s-1
  !
  ! When the continuum opacity is zero, the density of the molecule being
  ! studied does not really enter the calculation.
  !
  a_mol_using%density_mol = rdxx_cfg%n_x(rdxx_cfg%in_x)
  if (a_mol_using%density_mol .le. 1D-20) then
    ! If not set, set it to a non-harmful value.
    a_mol_using%density_mol = 1D0
  end if
  !
  if (rdxx_cfg%provideLength) then
    a_mol_using%length_scale = rdxx_cfg%length_scale ! cm
  else
    a_mol_using%length_scale = rdxx_cfg%Ncol_x(rdxx_cfg%iNcol_x) / &
                               a_mol_using%density_mol
  end if
  !
  ! Set the initial occupation
  a_mol_using%f_occupation = a_mol_using%level_list%weight * &
      exp(-a_mol_using%level_list%energy / a_mol_using%Tkin)
  ! Normalize
  a_mol_using%f_occupation = a_mol_using%f_occupation / &
                             sum(a_mol_using%f_occupation)
  !
  ! Set the density of the collisional partners
  do i=1, a_mol_using%colli_data%n_partner
    select case (a_mol_using%colli_data%list(i)%name_partner)
      case ('H2', 'h2')
      !
        a_mol_using%colli_data%list(i)%dens_partner = &
          rdxx_cfg%n_H2(rdxx_cfg%idens)
      !
      case ('o-H2', 'oH2')
      !
        if (rdxx_cfg%n_oH2(rdxx_cfg%idens) .le. 1D-20) then
          a_mol_using%colli_data%list(i)%dens_partner = &
            rdxx_cfg%n_H2(rdxx_cfg%idens) * 0.75D0
        else
          a_mol_using%colli_data%list(i)%dens_partner = &
            rdxx_cfg%n_oH2(rdxx_cfg%idens)
        end if
      !
      case ('p-H2', 'pH2')
      !
        if (rdxx_cfg%n_pH2(rdxx_cfg%idens) .le. 1D-20) then
          a_mol_using%colli_data%list(i)%dens_partner = &
            rdxx_cfg%n_H2(rdxx_cfg%idens) * 0.25D0
        else
          a_mol_using%colli_data%list(i)%dens_partner = &
            rdxx_cfg%n_pH2(rdxx_cfg%idens)
        end if
      !
      case ('H', 'h')
      !
        a_mol_using%colli_data%list(i)%dens_partner = &
          rdxx_cfg%n_HI(rdxx_cfg%idens)
      !
      case ('H+', 'h+')
      !
        a_mol_using%colli_data%list(i)%dens_partner = &
          rdxx_cfg%n_Hplus(rdxx_cfg%idens)
      !
      case ('E', 'e', 'E-', 'e-')
      !
        a_mol_using%colli_data%list(i)%dens_partner = &
          rdxx_cfg%n_E(rdxx_cfg%idens)
      !
      case ('He', 'HE')
      !
        a_mol_using%colli_data%list(i)%dens_partner = &
          rdxx_cfg%n_He(rdxx_cfg%idens)
      !
      case default
      !
        write(*, '(/A, A)') 'Unknown collisional partner: ', &
          a_mol_using%colli_data%list(i)%name_partner
        a_mol_using%colli_data%list(i)%dens_partner = 0D0
      !
    end select
    !
    write(rdxx_cfg%fU, '("!", ES12.4, " = ", A8)') &
      a_mol_using%colli_data%list(i)%dens_partner, &
      a_mol_using%colli_data%list(i)%name_partner
    write(*, '("!", ES12.4, " = ", A8)') &
      a_mol_using%colli_data%list(i)%dens_partner, &
      a_mol_using%colli_data%list(i)%name_partner
  end do
  !
end subroutine my_radex_prepare_molecule


subroutine my_radex_prepare_solver
end subroutine my_radex_prepare_solver


subroutine my_radex_prepare
  double precision lam_min, lam_max
  !
  !nullify(a_mol_using)
  allocate(a_mol_using)
  !
  ! Load the molecular data
  call load_moldata_LAMBDA(&
    combine_dir_filename(rdxx_cfg%dir_transition_rates, &
    rdxx_cfg%filename_molecule))
  !
  write(*, '(A, I5)') 'Number of levels: ', a_mol_using%n_level
  !
  statistic_equil_params%max_runtime_allowed = rdxx_cfg%max_code_run_time
  !
  ! Evolution time for the differential equation
  statistic_equil_params%t_max = rdxx_cfg%max_evol_time
  !
  ! Prepare for the storage
  statistic_equil_params%NEQ = a_mol_using%n_level
  statistic_equil_params%LIW = 20 + statistic_equil_params%NEQ
  statistic_equil_params%LRW = 22 + 9*statistic_equil_params%NEQ + &
                               statistic_equil_params%NEQ*statistic_equil_params%NEQ
  if (statistic_equil_params%NEQ .gt. a_mol_using%n_level) then
    if (allocated(statistic_equil_params%IWORK)) then
      deallocate(statistic_equil_params%IWORK, statistic_equil_params%RWORK)
    end if
  end if
  if (.not. allocated(statistic_equil_params%IWORK)) then
    allocate(statistic_equil_params%IWORK(statistic_equil_params%LIW), &
             statistic_equil_params%RWORK(statistic_equil_params%LRW))
  end if
  !
  lam_min = minval(a_mol_using%rad_data%list%lambda)/1.2D0 ! micron
  lam_max = maxval(a_mol_using%rad_data%list%lambda)*1.2D0 ! micron
  call make_local_cont_lut(lam_min, lam_max, 300)
  !
end subroutine my_radex_prepare


subroutine make_local_cont_lut(lam_min, lam_max, n)
  ! Prepare for the continuum background (usually just cmb).
  double precision, intent(in) :: lam_min, lam_max
  integer, intent(in) :: n
  integer i
  double precision dlam, lam, freq
  !
  if (.not. allocated(cont_lut%lam)) then
    cont_lut%n = n
    allocate(cont_lut%lam(cont_lut%n), &
             cont_lut%alpha(cont_lut%n), &
             cont_lut%J(cont_lut%n))
  end if
  !
  dlam = (lam_max - lam_min) / dble(n-1)
  do i=1, cont_lut%n
    cont_lut%lam(i) = lam_min + dlam * dble(i-1)
    cont_lut%alpha(i) = 0D0 ! absorption
    !
    lam = cont_lut%lam(i) + dlam * 0.5D0
    ! Energy per unit area per unit frequency per second per sqradian
    freq = phy_SpeedOfLight_CGS / (lam * phy_micron2cm)
    cont_lut%J(i) = planck_B_nu(rdxx_cfg%Tcmb, freq)
    !write(*,*) lam, freq
  end do
end subroutine make_local_cont_lut



function planck_B_lambda(T, lambda_CGS)
  double precision planck_B_lambda
  double precision, intent(in) :: T, lambda_CGS
  double precision tmp
  double precision, parameter :: TH = 1D-8
  tmp = (phy_hPlanck_CGS * phy_SpeedOfLight_CGS) / (lambda_CGS * phy_kBoltzmann_CGS * T)
  if (tmp .gt. TH) then
    tmp = exp(tmp) - 1D0
  end if
  planck_B_lambda = &
    2D0*phy_hPlanck_CGS * phy_SpeedOfLight_CGS**2 / lambda_CGS**5 / tmp
end function planck_B_lambda



function planck_B_nu(T, nu)
  double precision planck_B_nu
  double precision, intent(in) :: T, nu
  double precision tmp
  double precision, parameter :: TH = 1D-8
  tmp = (phy_hPlanck_CGS * nu) / (phy_kBoltzmann_CGS * T)
  if (tmp .gt. TH) then
    tmp = exp(tmp) - 1D0
  end if
  planck_B_nu = &
    2D0*phy_hPlanck_CGS * nu**3 / phy_SpeedOfLight_CGS**2 / tmp
end function planck_B_nu


end module my_radex
