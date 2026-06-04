// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get navHome => 'Início';

  @override
  String get navExercises => 'Exercícios';

  @override
  String get navRoutines => 'Treinos';

  @override
  String get navProfile => 'Perfil';

  @override
  String get sagaTabLabel => 'Saga';

  @override
  String get classSlotPlaceholder => 'O ferro lhe dará um nome.';

  @override
  String get classInitiate => 'Iniciante';

  @override
  String get classBerserker => 'Berserker';

  @override
  String get classBulwark => 'Baluarte';

  @override
  String get classSentinel => 'Sentinela';

  @override
  String get classPathfinder => 'Desbravador';

  @override
  String get classAtlas => 'Atlas';

  @override
  String get classAnchor => 'Âncora';

  @override
  String get classAscendant => 'Ascendente';

  @override
  String get dormantCardioCopy =>
      'As runas de cardio despertam em um capítulo futuro.';

  @override
  String get firstSetAwakensCopy => 'Sua primeira série desperta este caminho.';

  @override
  String get statsDeepDiveLabel => 'Estatísticas';

  @override
  String get titlesLabel => 'Títulos';

  @override
  String get historyLabel => 'Histórico';

  @override
  String get settingsLabel => 'Configurações';

  @override
  String get vitalityCopyUntested =>
      'Inexplorado — registre uma série para começar.';

  @override
  String get vitalityCopyDormant =>
      'Dormente. Treine este grupo para retomar o caminho.';

  @override
  String get vitalityRowUntestedSubtitle => 'Sem dados';

  @override
  String get vitalityStateBandActive => 'Ativo';

  @override
  String get vitalityStateBandWaning => 'Esmorecendo';

  @override
  String get vitalityStateBandDormant => 'Dormente';

  @override
  String get vitalityExplainerTitle => 'Vitalidade';

  @override
  String get vitalityExplainerDefinition =>
      'Vitalidade reflete o quão recente é seu treino para cada grupo muscular. É um indicador de quanto sua jornada está ativa, não da sua força.';

  @override
  String get vitalityExplainerHowItMoves => 'Como ela se move:';

  @override
  String get vitalityExplainerBandActive =>
      '66–100% — treino recente, no caminho.';

  @override
  String get vitalityExplainerBandWaning =>
      '34–65% — esmorecendo, o caminho se apaga.';

  @override
  String get vitalityExplainerBandDormant => '0–33% — o caminho silenciou.';

  @override
  String get vitalityExplainerRankSafety =>
      'Vitalidade NÃO afeta seu rank ou XP — esses são permanentes. Vitalidade é apenas um sinal de consistência.';

  @override
  String get withinRankXpSuffix => 'para o próximo rank';

  @override
  String get statsDeepDiveTitle => 'Estatísticas';

  @override
  String get vitalityTrendHeading => 'Tendência de Vitalidade — 90 dias';

  @override
  String get vitalityTrendHeadingShort => 'Tendência de Vitalidade';

  @override
  String get liveVitalitySectionHeading => 'Vitalidade Atual';

  @override
  String get volumePeakSectionHeading => 'Volume e Pico';

  @override
  String get peakLoadsSectionHeading => 'Cargas Máximas';

  @override
  String get peakLoadsEmpty => 'Nenhum pico registrado ainda.';

  @override
  String get weeklyVolumeUnit => 'séries';

  @override
  String get oneRmEstimateLabel => '1RM est.';

  @override
  String get chartXLabelToday => 'Hoje';

  @override
  String get chartXLabel90DaysAgo => 'há 90 dias';

  @override
  String chartXLabelDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count dias',
      one: 'há 1 dia',
    );
    return '$_temp0';
  }

  @override
  String get save => 'Salvar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get loadingOverlayStop => 'Parar';

  @override
  String get delete => 'Excluir';

  @override
  String get confirm => 'Confirmar';

  @override
  String get retry => 'Tentar novamente';

  @override
  String get dismiss => 'Dispensar';

  @override
  String get continueLabel => 'Continuar';

  @override
  String get logOut => 'Sair';

  @override
  String get done => 'Concluir';

  @override
  String get edit => 'Editar';

  @override
  String get create => 'Criar';

  @override
  String get add => 'Adicionar';

  @override
  String get skip => 'Pular';

  @override
  String get back => 'Voltar';

  @override
  String get backExitHint => 'Pressione voltar novamente para sair';

  @override
  String get close => 'Fechar';

  @override
  String get start => 'Iniciar';

  @override
  String get remove => 'Remover';

  @override
  String get discard => 'Descartar';

  @override
  String get resume => 'Retomar';

  @override
  String get clear => 'Limpar';

  @override
  String get replace => 'Substituir';

  @override
  String get undo => 'Desfazer';

  @override
  String get all => 'Todos';

  @override
  String get or => 'OU';

  @override
  String get loading => 'Carregando...';

  @override
  String get error => 'Algo deu errado';

  @override
  String get noResults => 'Nenhum resultado encontrado';

  @override
  String get emptyState => 'Nada aqui ainda';

  @override
  String get search => 'Buscar';

  @override
  String get email => 'E-mail';

  @override
  String get password => 'Senha';

  @override
  String get logIn => 'ENTRAR';

  @override
  String get signUp => 'CADASTRAR';

  @override
  String get forgotPassword => 'Esqueceu a senha?';

  @override
  String get sendResetEmail => 'Enviar E-mail de Recuperação';

  @override
  String get offlineBanner =>
      'Offline — alterações serão sincronizadas quando você voltar a ficar online';

  @override
  String pendingSyncSingular(int count) {
    return '$count alteração pendente';
  }

  @override
  String pendingSyncPlural(int count) {
    return '$count alterações pendentes';
  }

  @override
  String get today => 'Hoje';

  @override
  String get yesterday => 'Ontem';

  @override
  String daysAgo(int count) {
    return '$count dias atrás';
  }

  @override
  String weeksAgo(int count) {
    return '$count semanas atrás';
  }

  @override
  String monthsAgo(int count) {
    return '$count meses atrás';
  }

  @override
  String get muscleGroupChest => 'Peito';

  @override
  String get muscleGroupBack => 'Costas';

  @override
  String get muscleGroupLegs => 'Pernas';

  @override
  String get muscleGroupShoulders => 'Ombros';

  @override
  String get muscleGroupArms => 'Braços';

  @override
  String get muscleGroupCore => 'Core';

  @override
  String get muscleGroupCardio => 'Cardio';

  @override
  String get equipmentBarbell => 'Barra';

  @override
  String get equipmentDumbbell => 'Halter';

  @override
  String get equipmentCable => 'Cabo';

  @override
  String get equipmentMachine => 'Máquina';

  @override
  String get equipmentBodyweight => 'Peso Corporal';

  @override
  String get equipmentBands => 'Elásticos';

  @override
  String get equipmentKettlebell => 'Kettlebell';

  @override
  String get setTypeWorking => 'Normal';

  @override
  String get setTypeWarmup => 'Aquecimento';

  @override
  String get setTypeDropset => 'Drop Set';

  @override
  String get setTypeFailure => 'Até a Falha';

  @override
  String get recordTypeMaxWeight => 'Peso Máximo';

  @override
  String get recordTypeMaxReps => 'Reps Máximo';

  @override
  String get recordTypeMaxVolume => 'Volume Máximo';

  @override
  String get weightUnitKg => 'KG';

  @override
  String get weightUnitLbs => 'LBS';

  @override
  String get appName => 'RepSaga';

  @override
  String get welcomeBack => 'Bem-vindo de volta';

  @override
  String get createYourAccount => 'Crie sua conta';

  @override
  String get emailRequired => 'E-mail é obrigatório';

  @override
  String get emailInvalid => 'Insira um e-mail válido';

  @override
  String get passwordRequired => 'Senha é obrigatória';

  @override
  String get passwordTooShort => 'A senha deve ter pelo menos 6 caracteres';

  @override
  String get forgotPasswordHint =>
      'Digite seu e-mail acima e toque em \"Esqueceu a senha?\"';

  @override
  String get resetPassword => 'Redefinir Senha';

  @override
  String sendResetEmailTo(String email) {
    return 'Enviar e-mail de redefinição de senha para $email?';
  }

  @override
  String get resetEmailSent =>
      'E-mail de redefinição enviado. Verifique sua caixa de entrada.';

  @override
  String get continueWithGoogle => 'Continuar com Google';

  @override
  String get alreadyHaveAccount => 'Já tem uma conta? Entrar';

  @override
  String get dontHaveAccount => 'Não tem uma conta? Cadastrar';

  @override
  String get legalAgreePrefix => 'Ao continuar, você concorda com nossos ';

  @override
  String get termsOfService => 'Termos de Serviço';

  @override
  String get andSeparator => ' e ';

  @override
  String get privacyPolicy => 'Política de Privacidade';

  @override
  String get authErrorInvalidCredentials =>
      'E-mail ou senha incorretos. Tente novamente.';

  @override
  String get authErrorEmailNotConfirmed =>
      'Verifique sua caixa de entrada e confirme seu e-mail primeiro.';

  @override
  String get authErrorAlreadyRegistered =>
      'Uma conta com este e-mail já existe. Tente entrar.';

  @override
  String get authErrorRateLimit =>
      'Muitas tentativas. Aguarde um momento e tente novamente.';

  @override
  String get authErrorWeakPassword =>
      'A senha é muito fraca. Use pelo menos 6 caracteres.';

  @override
  String get authErrorNetwork =>
      'Sem conexão com a internet. Verifique sua rede e tente novamente.';

  @override
  String get authErrorTimeout => 'A solicitação expirou. Tente novamente.';

  @override
  String get authErrorTokenExpired =>
      'O link de confirmação expirou. Solicite um novo.';

  @override
  String get authErrorGeneric => 'Algo deu errado. Tente novamente.';

  @override
  String get checkYourInbox => 'Verifique sua caixa de entrada';

  @override
  String get confirmationSentTo => 'Enviamos um e-mail de confirmação para';

  @override
  String get confirmationSent => 'Enviamos um e-mail de confirmação';

  @override
  String get tapLinkToVerify =>
      'Toque no link do e-mail para verificar sua conta, depois volte e faça login.';

  @override
  String get emailResent => 'E-mail reenviado! Verifique sua caixa de entrada.';

  @override
  String get backToLogin => 'VOLTAR PARA LOGIN';

  @override
  String get didntReceiveResend => 'Não recebeu? Reenviar e-mail';

  @override
  String get onboardingHeadline => 'Registre cada rep,\nsempre';

  @override
  String get onboardingSubtitle =>
      'Registre treinos, quebre recordes pessoais e construa o físico que você deseja.';

  @override
  String get getStarted => 'COMEÇAR';

  @override
  String get setupProfile => 'Configure seu perfil';

  @override
  String get tellUsAboutYourself => 'Conte um pouco sobre você';

  @override
  String get displayName => 'Nome de exibição';

  @override
  String get fitnessLevel => 'Nível de condicionamento';

  @override
  String get howOftenTrain => 'Com que frequência você planeja treinar?';

  @override
  String get weeklyGoalHint =>
      'Sua meta semanal — você pode alterar a qualquer momento';

  @override
  String get letsGo => 'VAMOS LÁ';

  @override
  String get pleaseEnterName => 'Por favor, insira seu nome.';

  @override
  String get failedToSaveProfile => 'Falha ao salvar perfil. Tente novamente.';

  @override
  String get onboardingErrorOffline =>
      'Você está offline. Verifique sua conexão e tente novamente.';

  @override
  String get onboardingErrorSessionExpired =>
      'Sua sessão expirou. Faça login novamente.';

  @override
  String get onboardingErrorSessionExpiredCta => 'Entrar';

  @override
  String get onboardingErrorValidationGeneric =>
      'Verifique os campos preenchidos.';

  @override
  String onboardingErrorValidationField(String field, String message) {
    return '$field: $message';
  }

  @override
  String get fitnessLevelBeginner => 'Iniciante';

  @override
  String get fitnessLevelIntermediate => 'Intermediário';

  @override
  String get fitnessLevelAdvanced => 'Avançado';

  @override
  String get homeActionHeroCreateFirstRoutine => 'Criar primeira rotina';

  @override
  String get homeActionHeroFreeWorkout => 'Treino livre';

  @override
  String get homeActionHeroFreeWorkoutSubtitleWeekComplete => 'Semana completa';

  @override
  String homeActionHeroStartRoutine(String routineName) {
    return 'Iniciar $routineName';
  }

  @override
  String get homeActionHeroStartEyebrow => 'INICIAR';

  @override
  String get homeActionHeroFreeEyebrow => 'TREINO LIVRE';

  @override
  String get homeActionHeroWelcomeEyebrow => 'BEM-VINDO';

  @override
  String homeBucketDaysTrained(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString dias treinados',
      one: '1 dia treinado',
      zero: 'Nenhum dia treinado',
    );
    return '$_temp0';
  }

  @override
  String get homeBucketSectionTitle => 'Esta semana';

  @override
  String get homeBucketSpontaneousBadge => 'Livre';

  @override
  String get homeCharacterCardChevronHint =>
      'Toque para expandir detalhes do personagem';

  @override
  String homeClosestRankUp(String bodyPart, int xp, int rank) {
    return '◆ $bodyPart · $xp XP p/ rank $rank';
  }

  @override
  String get homeEditPlanLink => 'Editar plano →';

  @override
  String get homeFirstStepFallback =>
      'Comece sua jornada — primeiro set aguarda';

  @override
  String homeNudgeBodyPartTitleClose(String bodyPart, String titleName) {
    return 'Título de $bodyPart ao alcance: $titleName';
  }

  @override
  String homeNudgeCrossBuildClose(String titleName) {
    return 'Título Especial ao alcance: $titleName';
  }

  @override
  String homeNudgeRemainingWorkouts(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Faltam $countString treinos para fechar a semana',
      one: 'Falta 1 treino para fechar a semana',
    );
    return '$_temp0';
  }

  @override
  String homeNudgeStreakDays(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString dias de sequência',
      one: '1 dia de sequência',
    );
    return '$_temp0';
  }

  @override
  String get samePlanThisWeek => 'Mesmo plano esta semana?';

  @override
  String get myRoutines => 'MEUS TREINOS';

  @override
  String get seeAll => 'Ver tudo';

  @override
  String get createYourFirstRoutine => 'Crie Seu Primeiro Treino';

  @override
  String get homeStarterRoutinesLabel => 'Rotinas iniciais';

  @override
  String get heroUpNext => 'PRÓXIMO';

  @override
  String get heroYourFirstWorkout => 'SEU PRIMEIRO TREINO';

  @override
  String get heroNoPlan => 'SEM PLANO';

  @override
  String get heroNewWeek => 'NOVA SEMANA';

  @override
  String get planYourWeek => 'Planeje sua semana';

  @override
  String get pickRoutinesForWeek => 'Escolha treinos para a semana';

  @override
  String get quickWorkout => 'Treino rápido';

  @override
  String get startNewWeek => 'Começar nova semana';

  @override
  String nOfNDone(int completed, int total) {
    return '$completed de $total concluídos';
  }

  @override
  String exerciseCountDuration(int count, int minutes) {
    return '$count exercícios · ~$minutes min';
  }

  @override
  String get offlineStartWorkout =>
      'Iniciar um treino requer conexão com a internet';

  @override
  String get couldNotLoadExercises =>
      'Não foi possível carregar exercícios. Tente novamente.';

  @override
  String get lastSessionPrefix => 'Último: ';

  @override
  String get exercises => 'Exercícios';

  @override
  String get searchExercises => 'Buscar exercícios...';

  @override
  String get noExercisesMatchFilters =>
      'Nenhum exercício corresponde aos filtros';

  @override
  String get yourExercisesWillAppear => 'Seus exercícios aparecerão aqui';

  @override
  String get clearFilters => 'Limpar Filtros';

  @override
  String get exerciseDetails => 'Detalhes do Exercício';

  @override
  String get failedToLoadExercise => 'Falha ao carregar exercício';

  @override
  String get customExercise => 'Exercício personalizado';

  @override
  String get personalRecords => 'Recordes Pessoais';

  @override
  String get noRecordsYet => 'Nenhum recorde ainda';

  @override
  String get deleteExercise => 'Excluir Exercício';

  @override
  String deleteExerciseConfirm(String name) {
    return 'Tem certeza que deseja excluir \"$name\"?';
  }

  @override
  String get deleting => 'Excluindo...';

  @override
  String get imageStart => 'Início';

  @override
  String get imageEnd => 'Fim';

  @override
  String repsUnit(int count) {
    return '$count reps';
  }

  @override
  String get exerciseName => 'Nome do Exercício';

  @override
  String get nameRequired => 'Nome é obrigatório';

  @override
  String get nameTooShort => 'O nome deve ter pelo menos 2 caracteres';

  @override
  String get muscleGroup => 'Grupo Muscular';

  @override
  String get equipmentType => 'Tipo de Equipamento';

  @override
  String get selectMuscleAndEquipment =>
      'Selecione um grupo muscular e tipo de equipamento';

  @override
  String get sessionExpired => 'Sessão expirada. Faça login novamente.';

  @override
  String get description => 'Descrição';

  @override
  String get descriptionHint => 'Breve descrição do exercício (opcional)';

  @override
  String get formTips => 'Dicas de Forma';

  @override
  String get formTipsHint => 'Dicas de execução, uma por linha (opcional)';

  @override
  String get formTipsHelper => 'Insira cada dica em uma nova linha';

  @override
  String get aboutSection => 'SOBRE';

  @override
  String get formTipsSection => 'DICAS DE FORMA';

  @override
  String get finishWorkout => 'Finalizar Sessão';

  @override
  String get completeOneSet => 'Complete pelo menos uma série para finalizar';

  @override
  String get addFirstExercise => 'Adicione seu primeiro exercício';

  @override
  String get tapButtonToStart => 'Toque no botão abaixo para começar';

  @override
  String get addExercise => 'Adicionar Exercício';

  @override
  String get addSet => 'Adicionar Série';

  @override
  String get fillRemaining => 'Preencher restantes';

  @override
  String get filledRemainingSets => 'Séries restantes preenchidas';

  @override
  String get removeExerciseTitle => 'Remover Exercício?';

  @override
  String removeExerciseContent(String name) {
    return 'Remover $name e todas as suas séries?';
  }

  @override
  String get failedToDiscardWorkout =>
      'Falha ao descartar sessão. Tente novamente.';

  @override
  String get failedToSaveWorkout => 'Falha ao salvar treino. Tente novamente.';

  @override
  String get workoutSavedOffline =>
      'Treino salvo. Será sincronizado quando voltar a ficar online.';

  @override
  String get workoutSavedServerError =>
      'Erro no servidor — salvo localmente. Vamos tentar novamente em segundo plano.';

  @override
  String get setColumnSet => 'SÉRIE';

  @override
  String get setColumnWeight => 'PESO';

  @override
  String get setColumnReps => 'REPS';

  @override
  String get setColumnType => 'TIPO';

  @override
  String setDeleted(int number) {
    return 'Série $number excluída';
  }

  @override
  String get discardWorkoutTitle => 'Descartar Sessão?';

  @override
  String discardWorkoutContent(String duration) {
    return 'Você está no caminho há $duration. Descarte agora e o trabalho se perde.';
  }

  @override
  String get finishWorkoutTitle => 'Selar esta sessão?';

  @override
  String incompleteSetsWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Você tem $count séries incompletas',
      one: 'Você tem 1 série incompleta',
    );
    return '$_temp0';
  }

  @override
  String get addNotesHint => 'Adicionar notas (opcional)';

  @override
  String get keepGoing => 'Continuar Treinando';

  @override
  String get saveAndFinish => 'Salvar e Finalizar';

  @override
  String get resumeWorkoutTitle => 'Retomar sessão?';

  @override
  String get resumeWorkoutStaleTitle => 'Continuar de onde parou?';

  @override
  String workoutInProgress(String name) {
    return '\"$name\" ainda está em andamento.';
  }

  @override
  String workoutInterrupted(String age) {
    return 'Foi interrompido $age.';
  }

  @override
  String get resumeAnyway => 'Retomar mesmo assim';

  @override
  String get restTimerLabel => 'Descanso';

  @override
  String restTimerRemaining(String time) {
    return 'Descanso: $time restante';
  }

  @override
  String get subtract30Semantics => 'Subtrair 30 segundos';

  @override
  String get add30Semantics => 'Adicionar 30 segundos';

  @override
  String get skipRestSemantics => 'Pular descanso';

  @override
  String get lessThanAnHourAgo => 'há menos de uma hora';

  @override
  String hoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count horas',
      one: 'há 1 hora',
    );
    return '$_temp0';
  }

  @override
  String yesterdayAt(String time) {
    return 'ontem às $time';
  }

  @override
  String weekdayAt(String weekday, String time) {
    return '$weekday às $time';
  }

  @override
  String get history => 'Histórico';

  @override
  String get failedToLoadHistory => 'Falha ao carregar histórico';

  @override
  String get noWorkoutsYet => 'Nenhuma sessão ainda';

  @override
  String get completedWorkoutsAppear =>
      'Suas sessões concluídas aparecerão aqui';

  @override
  String get startFirstWorkout => 'Comece seu primeiro treino';

  @override
  String get failedToLoadWorkout => 'Falha ao carregar treino';

  @override
  String get workout => 'Treino';

  @override
  String get exerciseGeneric => 'Exercício';

  @override
  String get notes => 'Notas';

  @override
  String get workoutDetailTotalVolumeLabel => 'Volume total';

  @override
  String workoutDetailTotalVolumeValue(String volume) {
    return '$volume';
  }

  @override
  String get routines => 'Treinos';

  @override
  String get failedToLoadRoutines => 'Falha ao carregar treinos';

  @override
  String get myRoutinesSection => 'MEUS TREINOS';

  @override
  String get starterRoutinesSection => 'TREINOS INICIAIS';

  @override
  String get routinesEmptyTitle => 'Nenhum treino ainda';

  @override
  String get routinesEmptyBody =>
      'Planeje uma sequência de exercícios uma vez e reutilize a cada treino.';

  @override
  String get routinesEmptyCta => 'Criar treino';

  @override
  String get createRoutine => 'Criar Treino';

  @override
  String get editRoutine => 'Editar Treino';

  @override
  String get routineName => 'Nome do treino';

  @override
  String get failedToSaveRoutine => 'Falha ao salvar treino. Tente novamente.';

  @override
  String get setsLabel => 'Séries';

  @override
  String get restLabel => 'Descanso';

  @override
  String get duplicateAndEdit => 'Duplicar e Editar';

  @override
  String get deleteRoutine => 'Excluir Treino';

  @override
  String deleteRoutineConfirm(String name) {
    return 'Excluir \"$name\"? Esta ação não pode ser desfeita.';
  }

  @override
  String exercisesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercícios',
      one: '1 exercício',
    );
    return '$_temp0';
  }

  @override
  String get profile => 'Perfil';

  @override
  String get gymUser => 'Usuário';

  @override
  String get editDisplayName => 'Editar Nome';

  @override
  String get enterYourName => 'Digite seu nome';

  @override
  String get workouts => 'Treinos';

  @override
  String get memberSince => 'Membro desde';

  @override
  String get weightUnit => 'Unidade de Peso';

  @override
  String get weeklyGoal => 'Meta Semanal';

  @override
  String get dataManagement => 'GERENCIAMENTO DE DADOS';

  @override
  String get manageData => 'Gerenciar Dados';

  @override
  String get legal => 'JURÍDICO';

  @override
  String get sendCrashReports => 'Enviar relatórios de erro';

  @override
  String get crashReportsSubtitle =>
      'Ajude a melhorar o RepSaga enviando dados anônimos de falhas.';

  @override
  String get logOutConfirm => 'Tem certeza que deseja sair?';

  @override
  String get manageDataTitle => 'Gerenciar Dados';

  @override
  String get deleteWorkoutHistory => 'Excluir Histórico de Sessões';

  @override
  String workoutsWillBeRemoved(String count) {
    return '$count sessões serão removidas';
  }

  @override
  String get resetAllAccountData => 'Redefinir Todos os Dados';

  @override
  String get resetAllSubtitle => 'Remove tudo. Permanente.';

  @override
  String get deleteAccount => 'Excluir Conta';

  @override
  String get deleteAccountSubtitle =>
      'Excluir permanentemente sua conta e todos os dados';

  @override
  String get deleteAllHistoryTitle => 'Excluir todo o histórico de sessões?';

  @override
  String deleteAllHistoryContent(int count) {
    return 'Isso excluirá permanentemente todas as $count sessões e não pode ser desfeito.';
  }

  @override
  String get deleteHistoryButton => 'Excluir Histórico';

  @override
  String get areYouSure => 'Tem certeza?';

  @override
  String get yesDelete => 'Sim, Excluir';

  @override
  String get historyCleared => 'Histórico de sessões limpo';

  @override
  String failedToClearHistory(String message) {
    return 'Falha ao limpar histórico: $message';
  }

  @override
  String get resetAccountData => 'Redefinir Dados da Conta';

  @override
  String get resetAccountWarning =>
      'Isso excluirá permanentemente todas as sessões e recordes pessoais. Seus treinos e exercícios personalizados serão mantidos. Não há como desfazer.';

  @override
  String get typeResetToConfirm => 'Digite RESET para confirmar';

  @override
  String get resetAccountButton => 'Redefinir Conta';

  @override
  String get accountDataReset => 'Dados da conta redefinidos';

  @override
  String failedToResetData(String message) {
    return 'Falha ao redefinir dados: $message';
  }

  @override
  String get deleteAccountWarning =>
      'Isso excluirá permanentemente sua conta, todas as suas sessões, recordes pessoais, treinos e exercícios personalizados. Esta ação não pode ser desfeita.';

  @override
  String get typeDeleteToConfirm => 'Digite DELETE para confirmar';

  @override
  String get deleteAccountButton => 'Excluir Conta';

  @override
  String failedToDeleteAccount(String message) {
    return 'Falha ao excluir conta: $message';
  }

  @override
  String get prsRoutinesKept =>
      'Seus recordes pessoais e treinos serão mantidos.';

  @override
  String get workoutHistorySection => 'HISTÓRICO DE SESSÕES';

  @override
  String get dangerSection => 'PERIGO';

  @override
  String get privacySection => 'PRIVACIDADE';

  @override
  String get prsLabel => 'PRs';

  @override
  String perWeekLabel(int count) {
    return '${count}x por semana';
  }

  @override
  String get frequencyQuestion => 'Quantas vezes por semana você quer treinar?';

  @override
  String get profileBodyweightLabel => 'Peso corporal';

  @override
  String get profileBodyweightNotSet => 'Não definido';

  @override
  String get profileBodyweightHelper =>
      'Usado para calcular XP em exercícios de peso corporal como barra fixa, paralelas e flexões.';

  @override
  String profileBodyweightInvalidRange(String min, String max, String unit) {
    return 'Digite um valor entre $min e $max $unit';
  }

  @override
  String get bodyweightPromptTitle =>
      'Defina seu peso corporal para XP preciso';

  @override
  String get bodyweightPromptBody =>
      'Exercícios como barra fixa e paralelas contam seu peso como parte da carga.';

  @override
  String get bodyweightPromptSetNow => 'Definir agora';

  @override
  String get bodyweightPromptSkip => 'Pular';

  @override
  String get pleaseTryAgain => 'Tente novamente.';

  @override
  String get personalRecordsTitle => 'Recordes Pessoais';

  @override
  String get failedToLoadRecords => 'Falha ao carregar recordes';

  @override
  String get noRecordsYetTitle => 'Nenhum Recorde Ainda';

  @override
  String get completeWorkoutToTrack =>
      'Complete um treino para começar a registrar recordes';

  @override
  String get startWorkout => 'Iniciar Treino';

  @override
  String get newPrHeading => 'NOVO PR';

  @override
  String get firstWorkoutComplete => 'Primeiro Treino Concluído!';

  @override
  String get startingBenchmarks => 'Estes são seus primeiros registros';

  @override
  String get unknownExercise => 'Exercício Desconhecido';

  @override
  String get thisWeeksPlan => 'Plano da Semana';

  @override
  String get moreOptions => 'Mais opções';

  @override
  String get autoFill => 'Preencher automático';

  @override
  String get clearWeek => 'Limpar Semana';

  @override
  String get addRoutine => 'Adicionar Treino';

  @override
  String plannedReadyToGo(int count, int total) {
    return '$count/$total planejados — pronto para treinar';
  }

  @override
  String plannedThisWeek(int count, int total) {
    return '$count/$total planejados esta semana';
  }

  @override
  String get noRoutinesPlanned => 'Nenhum treino planejado esta semana';

  @override
  String get addRoutines => 'Adicionar Treinos';

  @override
  String get replacePlanTitle => 'Substituir plano atual?';

  @override
  String get replacePlanContent =>
      'O preenchimento automático substituirá seu plano atual pelos treinos mais usados.';

  @override
  String get clearWeekTitle => 'Limpar Semana';

  @override
  String get clearWeekContent => 'Começar do zero esta semana?';

  @override
  String get routineRemoved => 'Treino removido';

  @override
  String get unknownRoutine => 'Treino Desconhecido';

  @override
  String get addRoutinesSheet => 'Adicionar Treinos';

  @override
  String get createMoreRoutines => 'Crie mais treinos para adicioná-los aqui.';

  @override
  String addCountRoutines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ADICIONAR $count TREINOS',
      one: 'ADICIONAR 1 TREINO',
    );
    return '$_temp0';
  }

  @override
  String get createNewRoutine => 'Criar nova rotina';

  @override
  String get savedConfirmation => 'Salvo';

  @override
  String get copyFromPreviousSet => 'Copiar da série anterior';

  @override
  String get weekComplete => 'SEMANA COMPLETA';

  @override
  String get thisWeek => 'ESTA SEMANA';

  @override
  String get newWeekLink => 'NOVA SEMANA';

  @override
  String sessionsCount(int count) {
    return '$count sessões';
  }

  @override
  String prsCount(int count) {
    return '$count PRs';
  }

  @override
  String addToPlanPrompt(String name) {
    return '$name não está no seu plano ainda. Adicionar?';
  }

  @override
  String get syncFailureSingular => 'O treino não sincronizou';

  @override
  String syncFailurePlural(int count) {
    return '$count treinos não sincronizaram';
  }

  @override
  String get savedLocallyRetry =>
      'Salvo localmente. Tente novamente ou dispense.';

  @override
  String get offlineRetryHint =>
      'Você está offline — tente novamente quando voltar a ficar online';

  @override
  String get pendingSyncTitle => 'Sincronização Pendente';

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get allSynced => 'Tudo sincronizado!';

  @override
  String get syncedSuccessfully => 'Sincronizado com sucesso.';

  @override
  String get pendingActionSaveWorkout => 'Salvar treino';

  @override
  String get pendingActionUpdateRecords => 'Atualizar recordes';

  @override
  String get pendingActionMarkComplete => 'Marcar treino como concluído';

  @override
  String queuedAt(String time) {
    return 'Na fila às $time';
  }

  @override
  String retryCount(int count) {
    return '$count tentativas';
  }

  @override
  String get syncErrorRetryGeneric =>
      'Não foi possível sincronizar agora. Vamos tentar novamente em alguns instantes.';

  @override
  String get syncErrorOffline =>
      'Sem conexão. Os dados serão sincronizados quando voltar online.';

  @override
  String get syncErrorSessionExpired =>
      'Sessão expirada. Faça login novamente.';

  @override
  String get syncErrorUnknown =>
      'Algo deu errado. Vamos tentar novamente em alguns instantes.';

  @override
  String get syncErrorStructuralBody =>
      'Não foi possível enviar — entre em contato com o suporte.';

  @override
  String get syncDismissAction => 'Dispensar';

  @override
  String get pendingSyncBadgeSingular => '1 treino pendente de sincronização';

  @override
  String pendingSyncBadgePlural(int count) {
    return '$count treinos pendentes de sincronização';
  }

  @override
  String pendingSyncBadgeSemantics(String label) {
    return '$label. Toque para gerenciar.';
  }

  @override
  String get noExercisesFound => 'Nenhum exercício encontrado';

  @override
  String get failedToLoadExercises => 'Falha ao carregar exercícios';

  @override
  String get durationLessThanOneMin => '< 1m';

  @override
  String get enterWeight => 'Insira o peso';

  @override
  String get ok => 'OK';

  @override
  String get enterReps => 'Insira as reps';

  @override
  String get failedToLoadDocument => 'Falha ao carregar documento';

  @override
  String get discardWorkout => 'Descartar sessão';

  @override
  String get moveUp => 'Mover para cima';

  @override
  String get moveDown => 'Mover para baixo';

  @override
  String get swapExercise => 'Trocar exercício';

  @override
  String get removeExercise => 'Remover exercício';

  @override
  String swapExerciseConfirmTitle(String newExercise) {
    return 'Trocar para $newExercise?';
  }

  @override
  String swapExerciseConfirmBody(
    int count,
    String newExercise,
    String oldExercise,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Suas $count séries registradas vão contar',
      one: 'Sua $count série registrada vai contar',
    );
    return '$_temp0 para os recordes de $newExercise (não de $oldExercise).';
  }

  @override
  String get swapExerciseConfirmAction => 'Trocar';

  @override
  String addExerciseUndo(String name) {
    return '$name adicionado';
  }

  @override
  String get last30Days => '30d';

  @override
  String get last90Days => '90d';

  @override
  String get allTime => 'Tudo';

  @override
  String switchMetricTo(String metric) {
    return 'Mudar métrica para $metric';
  }

  @override
  String get couldNotLoadProgress => 'Não foi possível carregar progresso';

  @override
  String get logFirstSetToTrack =>
      'Registre sua primeira série para começar a acompanhar';

  @override
  String get chartMetricE1rm => 'e1RM';

  @override
  String get chartMetricWeight => 'Peso';

  @override
  String get chartWindowDays30 => '30 dias';

  @override
  String get chartWindowDays90 => '90 dias';

  @override
  String get chartWindowAllTime => 'todo o período';

  @override
  String workoutsLoggedKeepGoing(int count) {
    return '$count treinos registrados — continue assim';
  }

  @override
  String get oneWorkoutLoggedKeepGoing =>
      '1 treino registrado — continue assim';

  @override
  String holdingSteadyAt(String weight, String unit) {
    return 'Estável em $weight $unit';
  }

  @override
  String trendUp(String weight, String unit, String window) {
    return 'Subiu $weight $unit em $window';
  }

  @override
  String trendDown(String weight, String unit, String window) {
    return 'Desceu $weight $unit em $window';
  }

  @override
  String prMarkerAt(String weight, String unit) {
    return 'Marcador de PR em $weight $unit';
  }

  @override
  String setNumberSemantics(int number, String type) {
    return 'Série $number. Toque e segure para mudar o tipo: $type';
  }

  @override
  String setNumberCopySemantics(int number, String type) {
    return 'Série $number. Toque para copiar série anterior. Toque e segure para mudar o tipo: $type';
  }

  @override
  String get tooltipCopyLastSetAndChangeType =>
      'Toque: copiar última série\nSegure: mudar tipo';

  @override
  String get tooltipChangeType => 'Segure: mudar tipo';

  @override
  String get setCompleted => 'Série concluída';

  @override
  String get markSetAsDone => 'Marcar série como concluída';

  @override
  String get markSetAsDonePredictedPr =>
      'Marcar série como concluída — recorde previsto';

  @override
  String get reorderExercisesTooltip => 'Reordenar exercícios';

  @override
  String get exitReorderModeTooltip => 'Sair do modo de reordenação';

  @override
  String exerciseSemanticsLabel(String name) {
    return 'Exercício: $name. Toque para detalhes.';
  }

  @override
  String get fillRemainingSetsSemantics =>
      'Preencher séries restantes com os últimos valores';

  @override
  String get addExerciseToWorkoutSemantics => 'Adicionar exercício ao treino';

  @override
  String get searchExercisesToAddSemantics =>
      'Buscar exercícios para adicionar';

  @override
  String addExerciseSemantics(String name) {
    return 'Adicionar $name';
  }

  @override
  String get setTypeAbbrWorking => 'N';

  @override
  String get setTypeAbbrWarmup => 'AQ';

  @override
  String get setTypeAbbrDropset => 'Dr';

  @override
  String get setTypeAbbrFailure => 'F';

  @override
  String get setTypeAbbrWarmupShort => 'Aq';

  @override
  String lastSessionSemantics(String name, String date) {
    return 'Última sessão: $name, $date';
  }

  @override
  String get searchExercisesSemantics => 'Buscar exercícios';

  @override
  String exerciseItemSemantics(String name) {
    return 'Exercício: $name';
  }

  @override
  String get muscleGroupSemanticsPrefix => 'Grupo muscular';

  @override
  String get equipmentTypeSemanticsPrefix => 'Tipo de equipamento';

  @override
  String get deleteExerciseSemantics => 'Excluir exercício';

  @override
  String get exerciseNameDuplicate => 'Um exercício com este nome já existe';

  @override
  String daysAgoShort(int count) {
    return '${count}d atrás';
  }

  @override
  String weeksAgoShort(int count) {
    return '${count}sem atrás';
  }

  @override
  String monthsAgoShort(int count) {
    return '${count}m atrás';
  }

  @override
  String get routineNamePushDay => 'Dia de Empurrar';

  @override
  String get routineNamePullDay => 'Dia de Puxar';

  @override
  String get routineNameLegDay => 'Dia de Pernas';

  @override
  String get routineNameFullBody => 'Corpo Inteiro';

  @override
  String get routineNameUpperLowerUpper => 'Superior/Inferior — Superior';

  @override
  String get routineNameUpperLowerLower => 'Superior/Inferior — Inferior';

  @override
  String get routineNameFiveByFiveStrength => '5x5 Força';

  @override
  String get routineNameFullBodyBeginner => 'Corpo Inteiro Iniciante';

  @override
  String get routineNameArmsAndAbs => 'Braços e Abdômen';

  @override
  String get preferences => 'PREFERÊNCIAS';

  @override
  String get language => 'Idioma';

  @override
  String get sagaIntroStep1Title => 'SEU TREINO É SEU PERSONAGEM';

  @override
  String get sagaIntroStep1Body =>
      'Cada série concluída define quem você se torna. Treine, registre, evolua.';

  @override
  String get sagaIntroStep2Title => 'XP DE CADA SÉRIE, PR E MISSÃO';

  @override
  String get sagaIntroStep2Body =>
      'Volume, intensidade, recordes pessoais e missões semanais geram XP.';

  @override
  String sagaIntroStep3Title(int level, String rank) {
    return 'NÍVEL $level — $rank';
  }

  @override
  String get sagaIntroStep3Body =>
      'Sua jornada começa aqui. Continue treinando para subir de rank.';

  @override
  String get sagaIntroNext => 'PRÓXIMO';

  @override
  String get sagaIntroBegin => 'COMEÇAR';

  @override
  String get sagaIntroSkip => 'Pular';

  @override
  String get sagaRankRookie => 'NOVATO';

  @override
  String get sagaRankIron => 'FERRO';

  @override
  String get sagaRankCopper => 'BRONZE';

  @override
  String get sagaRankSilver => 'PRATA';

  @override
  String get sagaRankGold => 'OURO';

  @override
  String get sagaRankPlatinum => 'PLATINA';

  @override
  String get sagaRankDiamond => 'DIAMANTE';

  @override
  String get rankWord => 'RANK';

  @override
  String levelUpHeading(int level) {
    return 'NÍVEL $level';
  }

  @override
  String firstAwakeningHeading(String bodyPart) {
    return '$bodyPart DESPERTA';
  }

  @override
  String titleUnlockRankLabel(String bodyPart, int rank) {
    return 'TÍTULO DE $bodyPart · RANK $rank';
  }

  @override
  String titleUnlockCharacterLevelLabel(int level) {
    return 'NÍVEL DE PERSONAGEM $level';
  }

  @override
  String get titleUnlockCrossBuildLabel => 'TÍTULO DE DISTINÇÃO';

  @override
  String get equipTitleButton => 'EQUIPAR TÍTULO';

  @override
  String get equippedLabel => 'EQUIPADO';

  @override
  String get prChipLabel => 'PR';

  @override
  String get finishButtonLabel => 'FINALIZAR';

  @override
  String get finishWorkoutDisabledHint =>
      'Complete pelo menos uma série para finalizar.';

  @override
  String get addExerciseFabLabel => 'Adicionar exercício';

  @override
  String celebrationOverflowLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mais $count ranks — abrir Saga',
      one: 'Mais 1 rank — abrir Saga',
    );
    return '$_temp0';
  }

  @override
  String get celebrationOverflowTapHint => 'Toque para continuar';

  @override
  String get titlesScreenTitle => 'Títulos';

  @override
  String get titlesEmptyState =>
      'Conquiste seu primeiro título subindo de rank em algum grupo muscular.';

  @override
  String titlesProgressLabel(int earned, int total) {
    return '$earned de $total conquistados';
  }

  @override
  String titlesRowRankThreshold(int rank) {
    return 'Rank $rank';
  }

  @override
  String titlesRowCharacterLevel(int level) {
    return 'Nível $level';
  }

  @override
  String get titlesRowCrossBuild => 'Distinção';

  @override
  String get titlesSectionCharacterLevel => 'NÍVEL DE PERSONAGEM';

  @override
  String get titlesSectionCrossBuild => 'DISTINÇÃO';

  @override
  String get titlesRegionEquipped => 'Equipado';

  @override
  String get titlesRegionEarned => 'Conquistados';

  @override
  String get titlesRegionNext => 'Próximos';

  @override
  String get titlesRowEquipCta => 'Equipar';

  @override
  String get titlesEquippedTag => 'Em uso';

  @override
  String get titlesCharacterLabel => 'Personagem';

  @override
  String titlesCounterPill(int earned, int total) {
    return '$earned / $total conquistados';
  }

  @override
  String titlesNextSubBodyPart(String bodyPart, int remaining) {
    return '$bodyPart · faltam $remaining ranks';
  }

  @override
  String titlesNextSubBodyPartOne(String bodyPart) {
    return '$bodyPart · falta 1 rank';
  }

  @override
  String titlesNextSubCharacter(int remaining) {
    return 'Personagem · faltam $remaining níveis';
  }

  @override
  String get titlesNextSubCharacterOne => 'Personagem · falta 1 nível';

  @override
  String get titlesCrossBuildEspecial => 'Especial';

  @override
  String titlesCrossBuildBottleneck(String bodyPart) {
    return '◆ Falta 1 rank em $bodyPart';
  }

  @override
  String get classTaglineInitiate => 'o caminho começa';

  @override
  String get classTaglineBerserker => 'a fúria responde';

  @override
  String get classTaglineBulwark => 'o pilar se move';

  @override
  String get classTaglineSentinel => 'o sentinela desperta';

  @override
  String get classTaglinePathfinder => 'o chão segura';

  @override
  String get classTaglineAtlas => 'o ombro carrega';

  @override
  String get classTaglineAnchor => 'a linha aguenta';

  @override
  String get classTaglineAscendant => 'o equilíbrio foi conquistado';

  @override
  String get classChangeOverlaySubtitle => 'Sua jornada ganhou um nome.';

  @override
  String classChangePreviousLabel(String className) {
    return 'antes: $className';
  }

  @override
  String classChangeOverflowMore(int count) {
    return '+$count mais mudança de classe';
  }

  @override
  String crossBuildHintBroadShouldered(int gap, String muscleName) {
    return 'Domine os pilares superiores — peito, costas e ombros acima de rank 30, com dominância clara sobre membros inferiores. Falta $gap de rank em $muscleName.';
  }

  @override
  String crossBuildHintPillarWalker(int gap) {
    return 'Suas pernas devem falar mais alto que seus braços. Falta $gap de rank nas pernas.';
  }

  @override
  String crossBuildHintEvenHanded(int gap, String muscleName) {
    return 'Todo músculo no mesmo nível — nenhum elo fraco. Falta $gap de rank em $muscleName.';
  }

  @override
  String crossBuildHintIronBound(int gap, String muscleName) {
    return 'Peito, costas, pernas — os três pilares acima de rank 60. Falta $gap de rank em $muscleName.';
  }

  @override
  String crossBuildHintSagaForged(int gap, String muscleName) {
    return 'O fim da jornada começa aqui — todo atributo acima de rank 60. Falta $gap de rank em $muscleName.';
  }

  @override
  String get crossBuildHintSatisfied =>
      'Todas as condições atendidas — predicado satisfeito.';

  @override
  String get title_chest_r5_initiate_of_the_forge_name => 'Iniciado da Forja';

  @override
  String get title_chest_r5_initiate_of_the_forge_flavor =>
      'Primeira fagulha bateu no ferro.';

  @override
  String get title_chest_r10_plate_bearer_name => 'Carregador de Anilha';

  @override
  String get title_chest_r10_plate_bearer_flavor =>
      'A barra já confia no seu peito.';

  @override
  String get title_chest_r15_forge_marked_name => 'Marcado pela Forja';

  @override
  String get title_chest_r15_forge_marked_flavor =>
      'O calor mora onde o esterno encosta no ferro.';

  @override
  String get title_chest_r20_iron_chested_name => 'Peito de Ferro';

  @override
  String get title_chest_r20_iron_chested_flavor =>
      'Anilha vai, anilha vem — a caixa torácica responde.';

  @override
  String get title_chest_r25_anvil_heart_name => 'Coração-Bigorna';

  @override
  String get title_chest_r25_anvil_heart_flavor =>
      'Martelado, nunca entortado.';

  @override
  String get title_chest_r30_forge_born_name => 'Nascido na Forja';

  @override
  String get title_chest_r30_forge_born_flavor =>
      'Os veteranos procuram trinca no peitoral. Não acham.';

  @override
  String get title_chest_r40_bulwark_chested_name => 'Peito-Muralha';

  @override
  String get title_chest_r40_bulwark_chested_flavor =>
      'Muro não dobra. Você também não.';

  @override
  String get title_chest_r50_forge_plated_name => 'Blindado pela Forja';

  @override
  String get title_chest_r50_forge_plated_flavor =>
      'A armadura que a barra deita até virar do seu tamanho.';

  @override
  String get title_chest_r60_anvil_forged_name => 'Forjado na Bigorna';

  @override
  String get title_chest_r60_anvil_forged_flavor =>
      'Dez mil reps, uma forma só.';

  @override
  String get title_chest_r70_forge_heart_name => 'Coração da Forja';

  @override
  String get title_chest_r70_forge_heart_flavor =>
      'O fogo continuou aceso onde os outros apagaram.';

  @override
  String get title_chest_r80_heart_of_forge_name => 'Brasa da Forja';

  @override
  String get title_chest_r80_heart_of_forge_flavor => 'Sem você, o aço esfria.';

  @override
  String get title_chest_r90_forge_untouched_name => 'Forja Intocada';

  @override
  String get title_chest_r90_forge_untouched_flavor =>
      'O calor passa. Nada marca o peitoral.';

  @override
  String get title_chest_r99_the_anvil_name => 'A Bigorna';

  @override
  String get title_chest_r99_the_anvil_flavor =>
      'Cada anilha desta academia foi moldada em você.';

  @override
  String get title_back_r5_lattice_touched_name => 'Tocado pela Treliça';

  @override
  String get title_back_r5_lattice_touched_flavor =>
      'Asa começa por dentro da pele primeiro.';

  @override
  String get title_back_r10_wing_marked_name => 'Marcado pela Asa';

  @override
  String get title_back_r10_wing_marked_flavor =>
      'Sua sombra no chão é mais larga que ontem.';

  @override
  String get title_back_r15_rope_hauler_name => 'Puxa-Corda';

  @override
  String get title_back_r15_rope_hauler_flavor =>
      'O que estiver pendurado, você puxa.';

  @override
  String get title_back_r20_lat_crowned_name => 'Coroado das Costas';

  @override
  String get title_back_r20_lat_crowned_flavor =>
      'Duas placas sustentam sua silhueta.';

  @override
  String get title_back_r25_talon_backed_name => 'Costas-Garra';

  @override
  String get title_back_r25_talon_backed_flavor =>
      'A barra desce porque você mandou.';

  @override
  String get title_back_r30_wing_spread_name => 'Asa-Aberta';

  @override
  String get title_back_r30_wing_spread_flavor => 'Os portais já te respeitam.';

  @override
  String get title_back_r40_lattice_hauled_name => 'Treliça Puxada';

  @override
  String get title_back_r40_lattice_hauled_flavor =>
      'O ferro sobe e a treliça responde.';

  @override
  String get title_back_r50_wing_crowned_name => 'Asa-Coroada';

  @override
  String get title_back_r50_wing_crowned_flavor =>
      'A barra entorta. As asas levantam.';

  @override
  String get title_back_r60_lattice_spread_name => 'Treliça-Aberta';

  @override
  String get title_back_r60_lattice_spread_flavor =>
      'Vigas de catedral, montadas uma rep por vez.';

  @override
  String get title_back_r70_wing_storm_name => 'Asa-Tempestade';

  @override
  String get title_back_r70_wing_storm_flavor =>
      'O ar se mexe quando você se mexe.';

  @override
  String get title_back_r80_wing_of_storms_name => 'Asa das Tempestades';

  @override
  String get title_back_r80_wing_of_storms_flavor =>
      'Costas que o tempo se forma em volta.';

  @override
  String get title_back_r90_sky_lattice_name => 'Treliça do Céu';

  @override
  String get title_back_r90_sky_lattice_flavor =>
      'O que segura o céu, agora em você.';

  @override
  String get title_back_r99_the_lattice_name => 'A Treliça';

  @override
  String get title_back_r99_the_lattice_flavor =>
      'Cada cabo da academia obedece a você.';

  @override
  String get title_legs_r5_ground_walker_name => 'Pisador de Chão';

  @override
  String get title_legs_r5_ground_walker_flavor => 'A terra já sabe seu peso.';

  @override
  String get title_legs_r10_stone_stepper_name => 'Pisa-Pedra';

  @override
  String get title_legs_r10_stone_stepper_flavor =>
      'Pedrega se move quando você agacha.';

  @override
  String get title_legs_r15_pillar_apprentice_name => 'Aprendiz de Pilar';

  @override
  String get title_legs_r15_pillar_apprentice_flavor =>
      'As colunas estão decorando seu nome.';

  @override
  String get title_legs_r20_pillar_walker_name => 'Pilar-Andante';

  @override
  String get title_legs_r20_pillar_walker_flavor =>
      'Duas colunas onde antes tinha perna.';

  @override
  String get title_legs_r25_quarry_strider_name => 'Caminhante da Pedreira';

  @override
  String get title_legs_r25_quarry_strider_flavor =>
      'Pedra é só onde você começa.';

  @override
  String get title_legs_r30_mountain_strider_name => 'Caminhante da Montanha';

  @override
  String get title_legs_r30_mountain_strider_flavor =>
      'Subida é só mais uma série.';

  @override
  String get title_legs_r40_stone_strider_name => 'Pisa-Rocha';

  @override
  String get title_legs_r40_stone_strider_flavor =>
      'O chão racha antes de te segurar.';

  @override
  String get title_legs_r50_mountain_footed_name => 'Pé-de-Montanha';

  @override
  String get title_legs_r50_mountain_footed_flavor =>
      'Os alicerces se ajeitam ao redor da sua base.';

  @override
  String get title_legs_r60_mountain_rooted_name => 'Raiz-de-Montanha';

  @override
  String get title_legs_r60_mountain_rooted_flavor =>
      'Tempestade quebra antes de te tirar do chão.';

  @override
  String get title_legs_r70_pillar_footed_name => 'Pé-de-Pilar';

  @override
  String get title_legs_r70_pillar_footed_flavor =>
      'Trabalho de arquitetura, num corpo só.';

  @override
  String get title_legs_r80_pillar_of_storms_name => 'Pilar das Tempestades';

  @override
  String get title_legs_r80_pillar_of_storms_flavor =>
      'O vento desvia. Você fica.';

  @override
  String get title_legs_r90_mountain_untouched_name => 'Montanha Intocada';

  @override
  String get title_legs_r90_mountain_untouched_flavor =>
      'Erosão leva um milhão de anos. Você bota mais uma série.';

  @override
  String get title_legs_r99_the_pillar_name => 'O Pilar';

  @override
  String get title_legs_r99_the_pillar_flavor => 'Tira você dali e o teto cai.';

  @override
  String get title_shoulders_r5_burden_tester_name => 'Testa-Carga';

  @override
  String get title_shoulders_r5_burden_tester_flavor =>
      'Primeiro peso acima da cabeça — o céu reparou.';

  @override
  String get title_shoulders_r10_yoke_apprentice_name => 'Aprendiz da Canga';

  @override
  String get title_shoulders_r10_yoke_apprentice_flavor =>
      'O ferro pousa em você e fica quieto.';

  @override
  String get title_shoulders_r15_sky_reach_name => 'Alcança-Céu';

  @override
  String get title_shoulders_r15_sky_reach_flavor =>
      'Os braços acham o teto sem pensar.';

  @override
  String get title_shoulders_r20_atlas_touched_name => 'Tocado por Atlas';

  @override
  String get title_shoulders_r20_atlas_touched_flavor =>
      'Mitos antigos reconhecem o formato.';

  @override
  String get title_shoulders_r25_sky_vaulter_name => 'Salta-Céu';

  @override
  String get title_shoulders_r25_sky_vaulter_flavor =>
      'Para cima é onde a barra mora.';

  @override
  String get title_shoulders_r30_yoke_crowned_name => 'Canga-Coroada';

  @override
  String get title_shoulders_r30_yoke_crowned_flavor =>
      'O que pousa em você vira enfeite.';

  @override
  String get title_shoulders_r40_atlas_carried_name => 'Carrega-Atlas';

  @override
  String get title_shoulders_r40_atlas_carried_flavor =>
      'O mundo não pesa tanto quanto promete.';

  @override
  String get title_shoulders_r50_sky_yoked_name => 'Canga-do-Céu';

  @override
  String get title_shoulders_r50_sky_yoked_flavor =>
      'O horizonte pendura no seu trapézio.';

  @override
  String get title_shoulders_r60_sky_vaulted_name => 'Abóboda-do-Céu';

  @override
  String get title_shoulders_r60_sky_vaulted_flavor =>
      'Os braços abrem espaço onde não tinha.';

  @override
  String get title_shoulders_r70_sky_held_name => 'Segura-Céu';

  @override
  String get title_shoulders_r70_sky_held_flavor =>
      'Solta você e a nuvem cai junto.';

  @override
  String get title_shoulders_r80_sky_sundered_name => 'Rasga-Céu';

  @override
  String get title_shoulders_r80_sky_sundered_flavor =>
      'O que você empurra abre o teto.';

  @override
  String get title_shoulders_r90_sky_untouched_name => 'Céu Intocado';

  @override
  String get title_shoulders_r90_sky_untouched_flavor =>
      'Tempestade passa por cima. Você não curva.';

  @override
  String get title_shoulders_r99_the_atlas_name => 'O Atlas';

  @override
  String get title_shoulders_r99_the_atlas_flavor =>
      'O peso inteiro do céu. Trabalho leve.';

  @override
  String get title_arms_r5_vein_stirrer_name => 'Mexe-Veia';

  @override
  String get title_arms_r5_vein_stirrer_flavor => 'O sangue já decora a rosca.';

  @override
  String get title_arms_r10_iron_fingered_name => 'Dedo-de-Ferro';

  @override
  String get title_arms_r10_iron_fingered_flavor => 'O que você pega, fica.';

  @override
  String get title_arms_r15_sinew_drawn_name => 'Tendão-Esticado';

  @override
  String get title_arms_r15_sinew_drawn_flavor =>
      'Cabo, corda, pegada — todos respondem.';

  @override
  String get title_arms_r20_marrow_cleaver_name => 'Racha-Tutano';

  @override
  String get title_arms_r20_marrow_cleaver_flavor =>
      'Cada rep corta mais fundo que a anterior.';

  @override
  String get title_arms_r25_steel_sleeved_name => 'Manga-de-Aço';

  @override
  String get title_arms_r25_steel_sleeved_flavor =>
      'A camiseta não acompanha. Para de tentar.';

  @override
  String get title_arms_r30_sinew_sworn_name => 'Tendão-Jurado';

  @override
  String get title_arms_r30_sinew_sworn_flavor =>
      'A fibra não desiste antes de você.';

  @override
  String get title_arms_r40_iron_knuckled_name => 'Punho-de-Ferro';

  @override
  String get title_arms_r40_iron_knuckled_flavor => 'O cabo entorta primeiro.';

  @override
  String get title_arms_r50_steel_forged_name => 'Forjado em Aço';

  @override
  String get title_arms_r50_steel_forged_flavor =>
      'Martelado até virar formato de quem ergue.';

  @override
  String get title_arms_r60_sinew_bound_name => 'Atado-na-Fibra';

  @override
  String get title_arms_r60_sinew_bound_flavor =>
      'Os cabos ficaram sem folga faz tempo.';

  @override
  String get title_arms_r70_iron_sleeved_name => 'Manga-de-Ferro';

  @override
  String get title_arms_r70_iron_sleeved_flavor =>
      'Do nó dos dedos ao ombro, tudo carrega.';

  @override
  String get title_arms_r80_sinew_of_storms_name => 'Fibra das Tempestades';

  @override
  String get title_arms_r80_sinew_of_storms_flavor =>
      'O raio aprende o formato com você.';

  @override
  String get title_arms_r90_iron_untouched_name => 'Ferro Intocado';

  @override
  String get title_arms_r90_iron_untouched_flavor =>
      'Anilha entra. Anilha sai. O braço não se mexe.';

  @override
  String get title_arms_r99_the_sinew_name => 'O Tendão';

  @override
  String get title_arms_r99_the_sinew_flavor =>
      'O que precisar erguer aqui, você ergue.';

  @override
  String get title_core_r5_spine_tested_name => 'Coluna-Testada';

  @override
  String get title_core_r5_spine_tested_flavor =>
      'Primeira trava segurou — a barra ficou nivelada.';

  @override
  String get title_core_r10_core_forged_name => 'Core-Forjado';

  @override
  String get title_core_r10_core_forged_flavor =>
      'Linha do meio travada, costela ao quadril.';

  @override
  String get title_core_r15_pillar_spined_name => 'Coluna-Pilar';

  @override
  String get title_core_r15_pillar_spined_flavor =>
      'A barra pode tombar. Você não.';

  @override
  String get title_core_r20_iron_belted_name => 'Cinta-de-Ferro';

  @override
  String get title_core_r20_iron_belted_flavor =>
      'Cinto virou formalidade nesta altura.';

  @override
  String get title_core_r25_stonewall_name => 'Muralha-de-Pedra';

  @override
  String get title_core_r25_stonewall_flavor => 'Ar entra. Força sai.';

  @override
  String get title_core_r30_diamond_spine_name => 'Coluna-Diamante';

  @override
  String get title_core_r30_diamond_spine_flavor =>
      'Comprimido bastante, vira pedra preciosa.';

  @override
  String get title_core_r40_anchor_belted_name => 'Cinta-Âncora';

  @override
  String get title_core_r40_anchor_belted_flavor =>
      'Seja qual for a carga, o tronco segura.';

  @override
  String get title_core_r50_stone_cored_name => 'Núcleo-de-Pedra';

  @override
  String get title_core_r50_stone_cored_flavor =>
      'Bate no centro. Bate na parede.';

  @override
  String get title_core_r60_marrow_carved_name => 'Tutano-Talhado';

  @override
  String get title_core_r60_marrow_carved_flavor =>
      'Cada rep cortou um entalhe no osso.';

  @override
  String get title_core_r70_stone_spined_name => 'Coluna-de-Pedra';

  @override
  String get title_core_r70_stone_spined_flavor =>
      'As vértebras se empilham que nem alvenaria.';

  @override
  String get title_core_r80_spine_of_storms_name => 'Coluna das Tempestades';

  @override
  String get title_core_r80_spine_of_storms_flavor =>
      'Vento por entre árvores. O tronco não se mexe.';

  @override
  String get title_core_r90_marrow_untouched_name => 'Tutano Intocado';

  @override
  String get title_core_r90_marrow_untouched_flavor =>
      'O que rachar o corpo, para no centro.';

  @override
  String get title_core_r99_the_spine_name => 'A Coluna';

  @override
  String get title_core_r99_the_spine_flavor =>
      'Segura a barra como viga de capela.';

  @override
  String get title_wanderer_name => 'Andarilho';

  @override
  String get title_wanderer_flavor =>
      'O primeiro marco já ficou para trás. O mapa se abre.';

  @override
  String get title_path_trodden_name => 'Caminho-Trilhado';

  @override
  String get title_path_trodden_flavor =>
      'Vinte e cinco níveis. A estrada já conhece o seu peso.';

  @override
  String get title_path_sworn_name => 'Caminho-Jurado';

  @override
  String get title_path_sworn_flavor =>
      'Metade do caminho. Você não desiste mais.';

  @override
  String get title_path_forged_name => 'Caminho-Forjado';

  @override
  String get title_path_forged_flavor =>
      'Três quartos da subida. O caminho é forjado por você.';

  @override
  String get title_saga_scribed_name => 'Saga-Escrita';

  @override
  String get title_saga_scribed_flavor =>
      'Cem níveis. Seu nome está no códice.';

  @override
  String get title_saga_bound_name => 'Saga-Atado';

  @override
  String get title_saga_bound_flavor =>
      'Cento e vinte e cinco. A saga prende em você, e você prende de volta.';

  @override
  String get title_saga_eternal_name => 'Saga-Eterna';

  @override
  String get title_saga_eternal_flavor =>
      'Cento e quarenta e oito. A saga tem um nome agora, e é o seu.';

  @override
  String get title_pillar_walker_name => 'Andarilho de Pilares';

  @override
  String get title_pillar_walker_flavor =>
      'Você anda em pilares, não em braços. O chão sabe.';

  @override
  String get title_broad_shouldered_name => 'Ombro-Largo';

  @override
  String get title_broad_shouldered_flavor =>
      'Ombros que cangam, peito que é portão. Carregue o peso.';

  @override
  String get title_even_handed_name => 'Mão-Equilibrada';

  @override
  String get title_even_handed_flavor =>
      'Sem ponto fraco. Sem levantamento favorito. A forja inteira, em harmonia.';

  @override
  String get title_iron_bound_name => 'Atado-em-Ferro';

  @override
  String get title_iron_bound_flavor =>
      'Supino, remada, agachamento — todos atados em ferro. Os três grandes respondem a você.';

  @override
  String get title_saga_forged_name => 'Saga-Forjada';

  @override
  String get title_saga_forged_flavor =>
      'Cada track no sessenta. A saga foi forjada, e foi você quem forjou.';

  @override
  String get decrementWeight => 'Diminuir peso';

  @override
  String get incrementWeight => 'Aumentar peso';

  @override
  String get decrementReps => 'Diminuir repetições';

  @override
  String get incrementReps => 'Aumentar repetições';

  @override
  String weightValueSemantics(String formatted, String unit) {
    return 'Valor do peso: $formatted $unit. Toque para inserir o peso.';
  }

  @override
  String repsValueSemantics(int value) {
    return 'Valor das repetições: $value. Toque para inserir as repetições.';
  }

  @override
  String get restTimerDismiss => 'Dispensar timer de descanso';

  @override
  String workoutNameTapToRenameSemantics(String name) {
    return '$name. Toque para renomear o treino.';
  }

  @override
  String workoutDefaultName(String date) {
    return 'Treino — $date';
  }

  @override
  String get volumePeakBlockVolumeLabel => 'Volume';

  @override
  String get volumePeakBlockCargaPicoLabel => 'Carga pico';

  @override
  String get volumePeakBlockReferenciaLabel => 'Referência';

  @override
  String get volumePeakBlockSeries => 'séries';

  @override
  String get volumePeakBlockDeltaVsPrevWeek => 'vs semana passada';

  @override
  String get volumePeakBlockDeltaVsFourWeekMean => 'vs média (4 sem)';

  @override
  String get volumePeakBlockDeltaNoHistory => 'sem histórico';

  @override
  String get volumePeakBlockDeltaEstimated => 'estimado';

  @override
  String get volumePeakBlockDeltaAboveTarget => 'acima da meta';

  @override
  String get volumePeakBlockBadge30D => '30D';

  @override
  String get weeklyEngagementHeader => 'Engajamento da semana';

  @override
  String get engagementExplainerTitle => 'Como contamos os sets';

  @override
  String get engagementExplainerBody =>
      'Cada set conta para a parte do corpo com maior parcela na atribuição de XP. Se duas partes empatam na maior parcela, ambas contam. Isso evita contagem dupla de músculos não relacionados sem deixar de creditar exercícios compostos.';

  @override
  String get engagementLegendDone => 'Realizado';

  @override
  String get engagementLegendPlanned => 'Planejado';

  @override
  String daysTrainedCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString dias treinados',
      one: '1 dia treinado',
      zero: '0 dias treinados',
    );
    return '$_temp0';
  }

  @override
  String get addWorkout => '+ Adicionar treino';

  @override
  String softCapWarning(int count) {
    return 'Acima do seu limite semanal de $count';
  }

  @override
  String get spontaneousTag => 'Espontâneo';

  @override
  String get b1CopyDayZero => 'COMEÇO.\nO PIOR JÁ PASSOU.';

  @override
  String get b1CopyBaselineA => 'ENCERRADO.\nMAIS FORTE.';

  @override
  String get b1CopyBaselineB => 'CONSISTÊNCIA VENCE.';

  @override
  String get b1CopyPrAnticipatory => 'NOVO LIMITE.';

  @override
  String get b1CopyTitleAnticipatory => 'CONQUISTA DESPERTADA.';

  @override
  String b1CopyMaxLevelUp(int n) {
    return 'NÍVEL $n.\nA SAGA CONTINUA.';
  }

  @override
  String get b1CopyClassChangeOnly => 'NOVO LIMITE.';

  @override
  String get b3PrEyebrowSingle => '!! Recorde';

  @override
  String b3PrEyebrowMulti(int n) {
    return '!! $n Recordes';
  }

  @override
  String get b3PrCopySingle => 'VOCÊ QUEBROU TUDO.';

  @override
  String get b3PrCopyMulti => 'VOCÊ DESTRUIU TUDO.';

  @override
  String b3PrPillTemplate(String exercise, String weight, int reps) {
    return '$exercise · ${weight}kg × $reps';
  }

  @override
  String get b3TitleEyebrow => 'Título Desbloqueado';

  @override
  String get b3ClassEyebrow => 'Classe Desperta';

  @override
  String get b3ClassSubline => 'DESPERTOU.';

  @override
  String b2RankCopy(String bodyPart, String n) {
    return '$bodyPart · RANK $n';
  }

  @override
  String summarySagaNumber(int n) {
    return 'Saga $n';
  }

  @override
  String get summaryDayZero => '1ª saga';

  @override
  String summaryDurationSets(int minutes, int sets) {
    return '$minutes min · $sets séries';
  }

  @override
  String summaryTonnage(String kg) {
    return '$kg ton';
  }

  @override
  String get summaryNextStepLabel => 'Próximo passo';

  @override
  String summaryNextRank(int xp, String bodyPart, int n) {
    return 'Faltam $xp XP\npara $bodyPart rank $n.';
  }

  @override
  String summaryNextLevel(int ranks, int n) {
    return 'Faltam $ranks ranks\npara nível $n.';
  }

  @override
  String get summaryNewTitleLabel => 'Novo título';

  @override
  String get summaryEquipCta => 'EQUIPAR';

  @override
  String get summaryEquipLater => 'depois';

  @override
  String get summaryContinueCta => 'CONTINUAR';

  @override
  String get summaryShareCta => 'Compartilhar saga';

  @override
  String get summaryShareComingSoon => 'Compartilhar — em breve';

  @override
  String get shareSheetTitle => 'Compartilhar saga';

  @override
  String get shareSheetTakePhoto => 'Tirar foto';

  @override
  String get shareSheetFromGallery => 'Escolher da galeria';

  @override
  String get shareSheetNoPhoto => 'Sem foto · só a saga';

  @override
  String get sharePreviewRetake => 'Refazer';

  @override
  String get sharePreviewShare => 'Compartilhar';

  @override
  String get shareWordmark => 'REPSAGA';

  @override
  String get sharePermissionDenied =>
      'Acesso à câmera negado. Toque novamente para tentar.';

  @override
  String get sharePermissionPermanentlyDenied =>
      'Acesso à câmera bloqueado nas configurações.';

  @override
  String get shareRenderError =>
      'Não foi possível gerar o cartão. Tente novamente.';

  @override
  String get shareOpenSettings => 'Abrir configurações';

  @override
  String get summaryRankUpOverflowHeader => '+1 RANK · ABRIR SAGA';

  @override
  String get emptyGuardTitle => 'Encerrar treino?';

  @override
  String get emptyGuardBody => 'Nenhum exercício registrado.';

  @override
  String get emptyGuardDiscard => 'Descartar';

  @override
  String get emptyGuardContinue => 'Continuar treinando';

  @override
  String get postSessionFirstAwakeningSuffix => 'Desperto';

  @override
  String postSessionCascadeTruncationPill(String n) {
    return '+$n mais';
  }

  @override
  String get postSessionXpLabel => 'XP';

  @override
  String get postSessionTitleEquipped => 'Equipado ✓';

  @override
  String get postSessionTitleEquipFailed =>
      'Não foi possível equipar o título. Tente novamente.';

  @override
  String get cinematicSkipLabel => 'PULAR';

  @override
  String get postSessionDebriefEyebrow => 'Relatório da sessão';

  @override
  String get postSessionPrFlag => 'PR';

  @override
  String postSessionMoreLifts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count outros exercícios',
      one: '+1 outro exercício',
    );
    return '$_temp0';
  }

  @override
  String postSessionRankLabel(int n) {
    return 'Rank $n';
  }

  @override
  String postSessionRankUpArrow(int fromRank, int toRank) {
    return 'Rank $fromRank → $toRank';
  }

  @override
  String get postSessionWeightUnit => 'kg';

  @override
  String get postSessionLeaveTitle => 'Sair da pós-batalha?';

  @override
  String get postSessionLeaveCancel => 'Não';

  @override
  String get postSessionLeaveConfirm => 'Sair';

  @override
  String get postSessionXpEarnedLabel => 'XP GANHO';

  @override
  String get avatarPickerSheetTitle => 'Escolha a origem do avatar';

  @override
  String get avatarPickerCamera => 'Tirar foto';

  @override
  String get avatarPickerGallery => 'Escolher da galeria';

  @override
  String get avatarPickerCancel => 'Cancelar';

  @override
  String get avatarCropSheetTitle => 'Posicione seu avatar';

  @override
  String get avatarCropSheetConfirm => 'Usar esta';

  @override
  String get avatarCropSheetCancel => 'Cancelar';

  @override
  String get avatarUploadSuccess => 'Avatar atualizado.';

  @override
  String get avatarUploadFailed =>
      'Não consegui atualizar seu avatar. Tente de novo.';

  @override
  String avatarSemanticsLabel(String name) {
    return 'Avatar do perfil de $name';
  }

  @override
  String get cameraPermissionDeniedForAvatar =>
      'Acesso à câmera negado. Tente a galeria, ou abra as configurações para liberar o acesso.';

  @override
  String historyWeekLabel(String date) {
    return 'Semana de $date';
  }

  @override
  String historyWeekRollupSets(int sets) {
    return '$sets séries';
  }

  @override
  String historyCardXpEyebrow(int xp) {
    return '+$xp XP';
  }

  @override
  String historyCardPrCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PRs',
      one: '1 PR',
    );
    return '◆ $_temp0';
  }

  @override
  String historyDetailStripXpPart(int xp) {
    return '+$xp XP';
  }

  @override
  String historyDetailStripPrPart(int prs) {
    String _temp0 = intl.Intl.pluralLogic(
      prs,
      locale: localeName,
      other: '$prs PRs',
      one: '1 PR',
    );
    return '$_temp0';
  }

  @override
  String get historyWeekLabelCurrent => 'Esta semana';
}
