# Student Portfolios Documentation

## Purpose
A digital space for students to showcase their work and receive feedback from teachers and parents.

## Data Flow
- Student or Teacher uploads work (media/text) to the `Portfolio`.
- Teacher provides feedback on the entry.
- Parents can view the portfolio and feedback.

## API Endpoints / Server Actions
- `uploadPortfolioEntry(studentId, data)`: Adds an item to a student's portfolio.
- `addPortfolioFeedback(entryId, feedback)`: Teacher adds feedback to an entry.
- `getStudentPortfolio(studentId)`: Retrieves all entries for a student.

## AI Extension Hooks
- `portfolioContentAnalyzer.ts`: Categorizes portfolio entries by skill or subject.

## Logging Strategy
`console.log("[PORTFOLIO_UPLOAD]", { schoolId, userId, timestamp, metadata: { studentId, entryId } })`

## Future Scaling Notes
- Integration with Google Drive or Dropbox.
- Ability for students to self-reflect on their work within the portfolio.
