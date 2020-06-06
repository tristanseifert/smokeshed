# Smokeshed App Frameworks
Most of the app functionality is spread into separate frameworks, so that helper apps/XPC services can easily make use of the same functionality as the app without duplicating the code.

- **Smokeshop:** Implements a CoreData-based data store. It contains the model, persistence handling, as well as helpers to allow for more than one process to have read/write access to the store.
- **Waterpipe:** Image processing pipeline, including RAW processing and lens corrections.
- **Bowl:** Various utility classes, categories, and some common assets. Also contains logging handlers.

