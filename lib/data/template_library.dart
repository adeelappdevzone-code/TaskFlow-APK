import '../core/utils.dart';
import 'app_store.dart';
import 'models.dart';
import 'team_models.dart';
import 'team_store.dart';

// Ready-made workflow templates that ship with the app, and creating tasks
// from any template.

TemplateTask _t(String title, int day,
        {Priority p = Priority.medium, int? est, List<String> check = const []}) =>
    TemplateTask(
        title: title, offsetDays: day, priority: p, estimateMinutes: est, checklist: [...check]);

TaskTemplate _b(String id, String name, String description, String category, int color, String icon,
        List<TemplateTask> tasks) =>
    TaskTemplate(
      id: 'builtin-$id',
      name: name,
      title: tasks.first.title,
      description: description,
      createdAt: DateTime(2026),
      category: category,
      color: color,
      icon: icon,
      tasks: tasks,
      builtIn: true,
    );

/// The library that comes with the app.
final List<TaskTemplate> builtInTemplates = [
  _b('website', 'Website Project', 'Complete workflow for website design and development.',
      'Agency', 0xFF6366F1, 'web', [
    _t('Kickoff call and requirements', 0,
        p: Priority.high,
        est: 60,
        check: ['Goals and audience', 'Pages list', 'Brand assets', 'Deadline']),
    _t('Sitemap and wireframes', 2, est: 240),
    _t('Homepage design', 5, p: Priority.high, est: 480, check: ['Desktop', 'Tablet', 'Mobile']),
    _t('Inner pages design', 8, est: 480),
    _t('Client review of designs', 10, p: Priority.high, est: 60),
    _t('Front-end development', 12, est: 960),
    _t('Content upload', 16, est: 240),
    _t('Testing on devices and browsers', 18,
        p: Priority.high, est: 240, check: ['Chrome / Safari', 'Phone', 'Forms', 'Speed']),
    _t('Launch and handover', 20, p: Priority.high, est: 120),
  ]),
  _b('content', 'Content Marketing', 'Plan and run a month of content.', 'Marketing', 0xFF16A34A,
      'campaign', [
    _t('Content calendar for the month', 0, p: Priority.high, est: 120),
    _t('Keyword and topic research', 1, est: 180),
    _t('Write blog post 1', 3, est: 240),
    _t('Write blog post 2', 8, est: 240),
    _t('Design graphics for posts', 9, est: 180),
    _t('Publish and share', 10, est: 60),
    _t('Monthly results report', 28, est: 90),
  ]),
  _b('social', 'Social Media Campaign', 'Monthly social media content planning and posting.',
      'Marketing', 0xFFDB2777, 'social', [
    _t('Campaign brief and goals', 0, p: Priority.high, est: 60),
    _t('Create posts for week 1', 1, est: 240),
    _t('Create posts for week 2', 7, est: 240),
    _t('Create posts for weeks 3–4', 14, est: 360),
    _t('Schedule posts', 15, est: 60),
    _t('Reply to comments and messages', 16, est: 120),
    _t('Campaign report', 29, est: 90),
  ]),
  _b('seo', 'SEO Project', 'Full SEO workflow for better search rankings.', 'Marketing', 0xFF0EA5E9,
      'search', [
    _t('SEO audit', 0,
        p: Priority.high, est: 240, check: ['Speed', 'Indexing', 'Broken links', 'Mobile']),
    _t('Keyword research', 2, est: 240),
    _t('On-page fixes (titles, meta, headings)', 5, est: 360),
    _t('Technical fixes', 7, est: 360),
    _t('Content plan for target keywords', 9, est: 180),
    _t('Backlink outreach', 12, est: 480),
    _t('Rankings report', 30, est: 90),
  ]),
  _b('onboarding', 'Client Onboarding', 'Set up a new client from first contact to kickoff.',
      'Operations', 0xFFEA7A0C, 'people', [
    _t('Send proposal and contract', 0, p: Priority.high, est: 60),
    _t('Collect signed contract and payment', 2, p: Priority.high, est: 30),
    _t('Get access (website, social, analytics)', 3, est: 60),
    _t('Create shared folder and links', 3, est: 30),
    _t('Kickoff meeting', 5,
        p: Priority.high, est: 60, check: ['Agenda', 'Introduce team', 'Agree timeline']),
    _t('Send kickoff summary', 5, est: 30),
  ]),
  _b('brand', 'Brand Design', 'Brand identity from research to final delivery.', 'Agency',
      0xFF8B5CF6, 'brush', [
    _t('Brand questionnaire', 0, est: 60),
    _t('Mood board and research', 2, est: 240),
    _t('Logo concepts', 5, p: Priority.high, est: 480),
    _t('Client review of logo', 8, p: Priority.high, est: 60),
    _t('Colors and typography', 10, est: 180),
    _t('Brand guidelines document', 13, est: 360),
    _t('Final files delivery', 15,
        p: Priority.high, est: 120, check: ['SVG / PNG', 'Guidelines PDF', 'Social sizes']),
  ]),
  _b('app', 'Mobile App Development', 'From scope to store release.', 'Development', 0xFF1F6FEB,
      'phone', [
    _t('Scope and user stories', 0, p: Priority.high, est: 240),
    _t('UI design', 4, est: 960),
    _t('Backend and database setup', 8, est: 960),
    _t('Build main screens', 12, est: 1440),
    _t('Testing and bug fixes', 22, p: Priority.high, est: 960),
    _t('Store listing and release', 28, p: Priority.high, est: 240),
  ]),
  _b('launch', 'Product Launch', 'End-to-end product launch planning and execution.', 'Marketing',
      0xFF22C55E, 'rocket', [
    _t('Launch plan and date', 0, p: Priority.high, est: 120),
    _t('Landing page', 3, est: 480),
    _t('Launch email and posts', 7, est: 240),
    _t('Press and partner outreach', 9, est: 240),
    _t('Launch day', 14, p: Priority.high, est: 480),
    _t('Post-launch review', 21, est: 90),
  ]),
  _b('event', 'Event Planning', 'Plan and run a successful event.', 'Operations', 0xFFEF4444,
      'event', [
    _t('Budget and date', 0, p: Priority.high, est: 60),
    _t('Book venue', 2, p: Priority.high, est: 120),
    _t('Invitations', 5, est: 120),
    _t('Food, sound and decoration', 10, est: 180),
    _t('Final check with vendors', 18, p: Priority.high, est: 60),
    _t('Event day', 20, p: Priority.high, est: 480),
    _t('Thank-you messages and photos', 21, est: 60),
  ]),
  _b('hr', 'HR Onboarding', 'Onboarding and training plan for a new employee.', 'Operations',
      0xFF3B82F6, 'person', [
    _t('Prepare laptop and accounts', 0, p: Priority.high, est: 60),
    _t('Welcome and office tour', 1, est: 60),
    _t('Policies and tools training', 1, est: 120),
    _t('Meet the team', 2, est: 60),
    _t('First small project', 3, est: 480),
    _t('One-week check-in', 7, est: 30),
    _t('30-day review', 30, est: 60),
  ]),
  _b('weekly', 'Weekly Personal Review', 'Plan your week and look back on the last one.',
      'Personal', 0xFF7C3AED, 'task', [
    _t('Review last week', 0, est: 30, check: ['What got done', 'What slipped', 'Lessons']),
    _t('Plan this week', 0,
        p: Priority.high, est: 30, check: ['Top 3 goals', 'Block focus time', 'Clear inbox']),
  ]),
];

/// Every template I can use: built-in, mine and my teams'.
List<TaskTemplate> allTemplates() => [
      ...builtInTemplates,
      ...AppStore.instance.templates,
      ...TeamStore.instance.teamTemplates,
    ];

/// Creates the tasks of [t] starting on [start]: in [team] (assigned to
/// [assigneeId]; a plain member gets them all) or as personal tasks, then
/// in [projectId] when given. Returns how many were made.
Future<int> useTemplate(TaskTemplate t,
    {required DateTime start, Team? team, String? assigneeId, String? projectId}) async {
  final now = DateTime.now();
  final store = TeamStore.instance;
  final me = store.uid;
  var made = 0;
  for (final w in t.workflow) {
    final day = dateOnly(start).add(Duration(days: w.offsetDays));
    final task = TaskItem(
      id: newId(),
      title: w.title,
      description: made == 0 ? t.description : '',
      priority: w.priority,
      startAt: day,
      endAt: DateTime(day.year, day.month, day.day, 23, 59),
      createdAt: now,
      updatedAt: now,
      projectId: team == null ? projectId : null,
      assigneeId: team == null ? null : (store.isAdmin(team) ? assigneeId : me),
      estimateMinutes: w.estimateMinutes,
    );
    final checklist = [
      for (final (i, c) in w.checklist.indexed)
        ChecklistItem(
          id: newId(),
          taskId: task.id,
          title: c,
          isDone: false,
          sortOrder: i,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    if (team == null) {
      await AppStore.instance.saveTask(task, checklist, isNew: true);
    } else {
      store.saveTask(team, task, checklist, isNew: true);
    }
    made++;
  }
  return made;
}
