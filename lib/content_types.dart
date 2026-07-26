import 'package:flutter/material.dart';

class ContentTypeItem {
  final String label;
  final String type;
  final IconData icon;
  const ContentTypeItem(this.label, this.type, this.icon);
}

const List<ContentTypeItem> contentTypes = [
  ContentTypeItem('Syllabus', 'syllabus', Icons.description),
  ContentTypeItem('Notes (PDF)', 'notes', Icons.picture_as_pdf),
  ContentTypeItem('Videos', 'video', Icons.video_library),
  ContentTypeItem('Assignments', 'assignment', Icons.assignment),
  ContentTypeItem('Project', 'project', Icons.folder_special),
  ContentTypeItem('Announcement', 'announcement', Icons.campaign),
  ContentTypeItem('Result', 'result', Icons.grade),
  ContentTypeItem('Certificate', 'certificate', Icons.workspace_premium),
  ContentTypeItem('Reference', 'reference', Icons.menu_book),
  ContentTypeItem('Attendance', 'attendance', Icons.fact_check),
  ContentTypeItem('Leave and Delays', 'leave and delays', Icons.event_busy),
  ContentTypeItem('Messages', 'messages', Icons.message),
  ContentTypeItem('Time Table', 'time table', Icons.schedule),
  ContentTypeItem('Student Councelling', 'student councelling', Icons.support_agent),
  ContentTypeItem('Billing', 'billing', Icons.receipt_long),
];